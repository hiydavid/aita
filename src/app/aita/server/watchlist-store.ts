import {
  WATCHLIST_FLAGS,
  WATCHLIST_REVIEW_STATUSES,
  type WatchlistFlag,
  type WatchlistItem,
  type WatchlistResponse,
  type WatchlistReview,
  type WatchlistReviewStatus,
} from '../shared/app-state';
import type { LakebaseQuery } from './history-store';
import { dateText, initializeWatchlistReviewSchema, postgresRelation, timestampText } from './watchlist-schema';

interface WatchlistSummary {
  row_count: number;
  distinct_employee_id: number;
  null_employee_id: number;
  max_as_of_date: string | null;
}

interface WatchlistQuery {
  businessLine?: string;
  flag?: WatchlistFlag;
  reviewStatus?: WatchlistReviewStatus;
  page: number;
  pageSize: number;
}

interface WatchlistReviewInput {
  status: WatchlistReviewStatus;
  note?: string | null;
}

interface WatchlistMetadata {
  summary: WatchlistSummary;
  businessLines: string[];
}

export class LakebaseWatchlistStore {
  private query?: LakebaseQuery;
  private summary: WatchlistSummary = {
    row_count: 0,
    distinct_employee_id: 0,
    null_employee_id: 0,
    max_as_of_date: null,
  };
  private readonly relation: string;

  constructor(syncedTableName: string) {
    this.relation = postgresRelation(syncedTableName);
  }

  async initialize(query: LakebaseQuery): Promise<void> {
    this.query = query;
    await initializeWatchlistReviewSchema(query);
    this.summary = (await this.readMetadata()).summary;
  }

  getSummary(): WatchlistSummary {
    return this.summary;
  }

  async list(input: WatchlistQuery): Promise<WatchlistResponse> {
    const businessLine = input.businessLine ?? null;
    const flag = input.flag ?? null;
    const reviewStatus = input.reviewStatus ?? null;
    const offset = (input.page - 1) * input.pageSize;
    const parameters = [businessLine, flag, reviewStatus];
    const [metadata, totalsResult, itemResult] = await Promise.all([
      this.readMetadata(),
      this.run(
        `${this.filteredWatchlistCte()}
         SELECT COUNT(*) FILTER (
                  WHERE ($3::text IS NULL OR review_status = $3)
                )::integer AS total,
                COUNT(*) FILTER (WHERE review_status = 'reviewed')::integer AS reviewed,
                COUNT(*)::integer AS review_scope_total
         FROM filtered_watchlist`,
        parameters
      ),
      this.run(
        `${this.filteredWatchlistCte()}
         SELECT employee_id, business_line, risk_flags, reasons,
                signal_count::integer AS signal_count, as_of_date::text AS as_of_date,
                review_status, review_note, reviewer, review_created_at
         FROM filtered_watchlist
         WHERE ($3::text IS NULL OR review_status = $3)
         ORDER BY signal_count DESC, employee_id
         LIMIT $4 OFFSET $5`,
        [...parameters, input.pageSize, offset]
      ),
    ]);
    this.summary = metadata.summary;
    const totals = totalsResult.rows[0];
    const total = Number(totals?.total ?? 0);
    const totalPages = total === 0 ? 0 : Math.ceil(total / input.pageSize);
    const parityPassed =
      metadata.summary.row_count === metadata.summary.distinct_employee_id &&
      metadata.summary.null_employee_id === 0 &&
      metadata.summary.max_as_of_date !== null;
    return {
      items: itemResult.rows.map((row) => this.mapItem(row)),
      pagination: {
        page: input.page,
        pageSize: input.pageSize,
        total,
        totalPages,
      },
      filters: {
        businessLines: metadata.businessLines,
        flags: [...WATCHLIST_FLAGS],
        reviewStatuses: [...WATCHLIST_REVIEW_STATUSES],
      },
      reviewSummary: {
        reviewed: Number(totals?.reviewed ?? 0),
        total: Number(totals?.review_scope_total ?? 0),
      },
      freshness: {
        asOfDate: metadata.summary.max_as_of_date,
        stale: this.isStale(metadata.summary.max_as_of_date),
      },
      parity: {
        rowCount: metadata.summary.row_count,
        distinctEmployeeId: metadata.summary.distinct_employee_id,
        nullEmployeeId: metadata.summary.null_employee_id,
        passed: parityPassed,
      },
    };
  }

  async addReview(employeeId: string, reviewer: string, input: WatchlistReviewInput): Promise<WatchlistReview | null> {
    const note = input.note?.trim() || null;
    const result = await this.run(
      `INSERT INTO aita_app.watchlist_review_events (
         employee_id, as_of_date, status, note, reviewer
       )
       SELECT employee_id, as_of_date, $2, $3, $4
       FROM ${this.relation}
       WHERE employee_id = $1
       ORDER BY as_of_date DESC
       LIMIT 1
       RETURNING status AS review_status, note AS review_note, reviewer,
                 created_at AS review_created_at`,
      [employeeId, input.status, note, reviewer]
    );
    const row = result.rows[0];
    return row ? this.mapReview(row) : null;
  }

  private filteredWatchlistCte(): string {
    return `WITH latest_review AS (
              SELECT DISTINCT ON (employee_id, as_of_date)
                     employee_id, as_of_date, status, note, reviewer, created_at
              FROM aita_app.watchlist_review_events
              ORDER BY employee_id, as_of_date, created_at DESC, event_id DESC
            ),
            filtered_watchlist AS (
              SELECT watchlist.employee_id, watchlist.business_line,
                     watchlist.risk_flags, watchlist.reasons, watchlist.signal_count,
                     watchlist.as_of_date,
                     COALESCE(review.status, 'unreviewed') AS review_status,
                     review.note AS review_note,
                     review.reviewer,
                     review.created_at AS review_created_at
              FROM ${this.relation} AS watchlist
              LEFT JOIN latest_review AS review
                ON review.employee_id = watchlist.employee_id
               AND review.as_of_date = watchlist.as_of_date
              WHERE ($1::text IS NULL OR watchlist.business_line = $1)
                AND ($2::text IS NULL OR watchlist.risk_flags @> to_jsonb(ARRAY[$2::text]))
            )`;
  }

  private async readMetadata(): Promise<WatchlistMetadata> {
    const [summaryResult, businessLineResult] = await Promise.all([
      this.run(`
        SELECT COUNT(*)::integer AS row_count,
               COUNT(DISTINCT employee_id)::integer AS distinct_employee_id,
               COUNT(*) FILTER (WHERE employee_id IS NULL)::integer AS null_employee_id,
               MAX(as_of_date)::text AS max_as_of_date
        FROM ${this.relation}
      `),
      this.run(`
        SELECT DISTINCT business_line
        FROM ${this.relation}
        WHERE business_line IS NOT NULL
        ORDER BY business_line
      `),
    ]);
    const row = summaryResult.rows[0];
    return {
      summary: {
        row_count: Number(row?.row_count ?? 0),
        distinct_employee_id: Number(row?.distinct_employee_id ?? 0),
        null_employee_id: Number(row?.null_employee_id ?? 0),
        max_as_of_date: dateText(row?.max_as_of_date),
      },
      businessLines: businessLineResult.rows.map((businessLine) => String(businessLine.business_line)),
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
      asOfDate: dateText(row.as_of_date) ?? 'Unknown',
      review: this.mapReview(row),
    };
  }

  private mapReview(row: Record<string, unknown>): WatchlistReview {
    const status = row.review_status ?? 'unreviewed';
    if (!this.isReviewStatus(status)) throw new Error('Unsupported watchlist review status');
    return {
      status,
      note: typeof row.review_note === 'string' ? row.review_note : null,
      reviewer: typeof row.reviewer === 'string' ? row.reviewer : null,
      createdAt: timestampText(row.review_created_at),
    };
  }

  private isReviewStatus(value: unknown): value is WatchlistReviewStatus {
    return typeof value === 'string' && WATCHLIST_REVIEW_STATUSES.some((status) => status === value);
  }

  private isStale(asOfDate: string | null): boolean {
    if (!asOfDate) return true;
    const ageMs = Date.now() - new Date(`${asOfDate}T00:00:00Z`).getTime();
    return ageMs > 45 * 24 * 60 * 60 * 1000;
  }

  private run(text: string, params?: unknown[]) {
    if (!this.query) throw new Error('Lakebase watchlist store is not initialized');
    return this.query(text, params);
  }
}
