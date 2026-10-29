import type { AgentKey, SqlEvidence } from './routing';

export const WATCHLIST_FLAGS = [
  'stalled_high_performer',
  'disengaging',
  'team_at_risk',
  'hard_to_backfill_risk',
] as const;

export type WatchlistFlag = (typeof WATCHLIST_FLAGS)[number];

export interface WatchlistItem {
  employeeId: string;
  businessLine: string;
  riskFlags: WatchlistFlag[];
  reasons: string[];
  signalCount: number;
  asOfDate: string;
}

export interface WatchlistResponse {
  items: WatchlistItem[];
  pagination: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
  filters: {
    businessLines: string[];
    flags: WatchlistFlag[];
  };
  freshness: {
    asOfDate: string | null;
    stale: boolean;
  };
  parity: {
    rowCount: number;
    distinctEmployeeId: number;
    nullEmployeeId: number;
    passed: boolean;
  };
}

export interface HistoryTurnMetadata {
  routedAgents: AgentKey[];
  genieConversationIds: Partial<Record<AgentKey, string>>;
  generatedSql: Partial<Record<AgentKey, SqlEvidence[]>>;
  latencyMs?: number;
}

export interface HistoryMessage {
  id: string;
  turnIndex: number;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  createdAt: string;
  metadata?: HistoryTurnMetadata;
}

export interface HistorySummary {
  id: string;
  title: string;
  messageCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface HistoryDetail extends HistorySummary {
  messages: HistoryMessage[];
}

export interface HistoryListResponse {
  conversations: HistorySummary[];
  retentionDays: number;
}
