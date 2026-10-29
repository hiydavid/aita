import type { LakebaseQuery } from './history-store';

export async function initializeWatchlistReviewSchema(query: LakebaseQuery): Promise<void> {
  await query('CREATE SCHEMA IF NOT EXISTS aita_app');
  await query(`
    CREATE TABLE IF NOT EXISTS aita_app.watchlist_review_events (
      event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_id TEXT NOT NULL,
      as_of_date DATE NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('unreviewed', 'in_review', 'reviewed')),
      note TEXT CHECK (note IS NULL OR char_length(note) <= 500),
      reviewer TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
    )
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS watchlist_review_events_latest_idx
    ON aita_app.watchlist_review_events (
      employee_id, as_of_date, created_at DESC, event_id DESC
    )
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS watchlist_review_events_status_idx
    ON aita_app.watchlist_review_events (status, created_at DESC)
  `);
}

export function postgresRelation(syncedTableName: string): string {
  const parts = syncedTableName.split('.');
  if (parts.length !== 2 && parts.length !== 3) {
    throw new Error('LAKEBASE_SYNCED_TABLE must be a schema.table or catalog.schema.table name');
  }
  const relationParts = parts.slice(-2);
  if (!relationParts.every((part) => /^[A-Za-z_][A-Za-z0-9_-]*$/.test(part))) {
    throw new Error('LAKEBASE_SYNCED_TABLE contains an unsupported identifier');
  }
  return relationParts.map((part) => `"${part}"`).join('.');
}

export function dateText(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value !== 'string') return null;
  const match = value.match(/^\d{4}-\d{2}-\d{2}/);
  if (match) return match[0];
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString().slice(0, 10);
}

export function timestampText(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (!(value instanceof Date) && typeof value !== 'string' && typeof value !== 'number') return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}
