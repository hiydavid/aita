import { WATCHLIST_FLAGS, type WatchlistFlag, type WatchlistItem, type WatchlistResponse } from '../shared/app-state';
import type { LakebaseQuery } from './history-store';

interface WatchlistSummary {
  row_count: number;
  distinct_employee_id: number;
  null_employee_id: number;
  max_as_of_date: string | null;
}

interface WatchlistQuery {
  businessLine?: string;
  flag?: WatchlistFlag;
  page: number;
  pageSize: number;
}

export class LakebaseWatchlistStore {
  private query?: LakebaseQuery;
  private summary: WatchlistSummary = {
    row_count: 0,
    distinct_employee_id: 0,
    null_employee_id: 0,
    max_as_of_date: null,
  };
  private businessLines: string[] = [];

  async initialize(query: LakebaseQuery): Promise<void> {
    this.query = query;
    const [summaryResult, businessLineResult] = await Promise.all([
      query(`
        SELECT COUNT(*)::integer AS row_count,
               COUNT(DISTINCT employee_id)::integer AS distinct_employee_id,
               COUNT(*) FILTER (WHERE employee_id IS NULL)::integer AS null_employee_id,
               MAX(as_of_date)::text AS max_as_of_date
        FROM aita_gold.talent_watchlist_serving
      `),
      query(`
        SELECT DISTINCT business_line
        FROM aita_gold.talent_watchlist_serving
        WHERE business_line IS NOT NULL
        ORDER BY business_line
      `),
    ]);
    const rawSummary = summaryResult.rows[0];
    if (rawSummary) {
      this.summary = {
        row_count: Number(rawSummary.row_count),
        distinct_employee_id: Number(rawSummary.distinct_employee_id),
        null_employee_id: Number(rawSummary.null_employee_id),
        max_as_of_date: this.toDateText(rawSummary.max_as_of_date),
      };
    }
    this.businessLines = businessLineResult.rows.map((row) => String(row.business_line));
  }

  getSummary(): WatchlistSummary {
    return this.summary;
  }

  async list(input: WatchlistQuery): Promise<WatchlistResponse> {
    const businessLine = input.businessLine ?? null;
    const flag = input.flag ?? null;
    const offset = (input.page - 1) * input.pageSize;
    const [countResult, itemResult] = await Promise.all([
      this.run(
        `SELECT COUNT(*)::integer AS total
         FROM aita_gold.talent_watchlist_serving
         WHERE ($1::text IS NULL OR business_line = $1)
           AND ($2::text IS NULL OR risk_flags @> to_jsonb(ARRAY[$2::text]))`,
        [businessLine, flag]
      ),
      this.run(
        `SELECT employee_id, business_line, risk_flags, reasons,
                signal_count::integer AS signal_count, as_of_date::text AS as_of_date
         FROM aita_gold.talent_watchlist_serving
         WHERE ($1::text IS NULL OR business_line = $1)
           AND ($2::text IS NULL OR risk_flags @> to_jsonb(ARRAY[$2::text]))
         ORDER BY signal_count DESC, employee_id
         LIMIT $3 OFFSET $4`,
        [businessLine, flag, input.pageSize, offset]
      ),
    ]);
    const total = Number(countResult.rows[0]?.total ?? 0);
    const totalPages = total === 0 ? 0 : Math.ceil(total / input.pageSize);
    const parityPassed =
      this.summary.row_count === this.summary.distinct_employee_id &&
      this.summary.null_employee_id === 0 &&
      this.summary.max_as_of_date !== null;
    return {
      items: itemResult.rows.map((row) => this.mapItem(row)),
      pagination: {
        page: input.page,
        pageSize: input.pageSize,
        total,
        totalPages,
      },
      filters: {
        businessLines: this.businessLines,
        flags: [...WATCHLIST_FLAGS],
      },
      freshness: {
        asOfDate: this.summary.max_as_of_date,
        stale: this.isStale(this.summary.max_as_of_date),
      },
      parity: {
        rowCount: this.summary.row_count,
        distinctEmployeeId: this.summary.distinct_employee_id,
        nullEmployeeId: this.summary.null_employee_id,
        passed: parityPassed,
      },
    };
  }

  private mapItem(row: Record<string, unknown>): WatchlistItem {
    const riskFlags = Array.isArray(row.risk_flags)
      ? row.risk_flags.filter((flag): flag is WatchlistFlag => WATCHLIST_FLAGS.some((knownFlag) => knownFlag === flag))
      : [];
    return {
      employeeId: String(row.employee_id),
      businessLine: String(row.business_line),
      riskFlags,
      reasons: Array.isArray(row.reasons) ? row.reasons.map(String) : [],
      signalCount: Number(row.signal_count),
      asOfDate: this.toDateText(row.as_of_date) ?? 'Unknown',
    };
  }

  private isStale(asOfDate: string | null): boolean {
    if (!asOfDate) return true;
    const ageMs = Date.now() - new Date(`${asOfDate}T00:00:00Z`).getTime();
    return ageMs > 45 * 24 * 60 * 60 * 1000;
  }

  private toDateText(value: unknown): string | null {
    if (value === null || value === undefined) return null;
    if (value instanceof Date) return value.toISOString().slice(0, 10);
    if (typeof value !== 'string') return null;
    const text = value;
    const match = text.match(/^\d{4}-\d{2}-\d{2}/);
    if (match) return match[0];
    const date = new Date(text);
    return Number.isNaN(date.getTime()) ? null : date.toISOString().slice(0, 10);
  }

  private run(text: string, params?: unknown[]) {
    if (!this.query) throw new Error('Lakebase watchlist store is not initialized');
    return this.query(text, params);
  }
}
