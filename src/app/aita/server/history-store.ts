import type { HistoryDetail, HistoryMessage, HistorySummary, HistoryTurnMetadata } from '../shared/app-state';
import { AGENT_KEYS, type AgentKey, type SqlEvidence, type TurnMetadataInput } from '../shared/routing';

export type LakebaseQuery = (text: string, params?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;

export class LakebaseHistoryStore {
  private query?: LakebaseQuery;

  async initialize(query: LakebaseQuery): Promise<void> {
    this.query = query;
    await query(`
      CREATE TABLE IF NOT EXISTS aita_app.turn_metadata (
        thread_id UUID NOT NULL,
        turn_index INTEGER NOT NULL,
        routed_agents TEXT[] NOT NULL DEFAULT '{}',
        genie_conversation_ids JSONB NOT NULL DEFAULT '{}',
        generated_sql JSONB NOT NULL DEFAULT '{}',
        latency_ms INTEGER,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (thread_id, turn_index),
        FOREIGN KEY (thread_id, turn_index)
          REFERENCES aita_app.messages(thread_id, turn_index) ON DELETE CASCADE
      )
    `);
  }

  async list(userId: string): Promise<HistorySummary[]> {
    await this.purgeExpired();
    const result = await this.run(
      `SELECT threads.id, threads.title, threads.created_at, threads.updated_at,
              COUNT(messages.id)::integer AS message_count
       FROM aita_app.threads AS threads
       LEFT JOIN aita_app.messages AS messages ON messages.thread_id = threads.id
       WHERE threads.user_id = $1
       GROUP BY threads.id, threads.title, threads.created_at, threads.updated_at
       ORDER BY threads.updated_at DESC`,
      [userId]
    );
    return result.rows.map((row) => this.mapSummary(row));
  }

  async get(threadId: string, userId: string): Promise<HistoryDetail | null> {
    await this.purgeExpired();
    const threadResult = await this.run(
      `SELECT threads.id, threads.title, threads.created_at, threads.updated_at,
              COUNT(messages.id)::integer AS message_count
       FROM aita_app.threads AS threads
       LEFT JOIN aita_app.messages AS messages ON messages.thread_id = threads.id
       WHERE threads.id = $1 AND threads.user_id = $2
       GROUP BY threads.id, threads.title, threads.created_at, threads.updated_at`,
      [threadId, userId]
    );
    const thread = threadResult.rows[0];
    if (!thread) return null;

    const messageResult = await this.run(
      `SELECT messages.id, messages.turn_index, messages.role, messages.content,
              messages.created_at, metadata.routed_agents,
              metadata.genie_conversation_ids, metadata.generated_sql, metadata.latency_ms
       FROM aita_app.messages AS messages
       INNER JOIN aita_app.threads AS threads
         ON threads.id = messages.thread_id AND threads.user_id = $2
       LEFT JOIN aita_app.turn_metadata AS metadata
         ON metadata.thread_id = messages.thread_id
        AND metadata.turn_index = messages.turn_index
       WHERE messages.thread_id = $1
       ORDER BY messages.turn_index`,
      [threadId, userId]
    );
    return {
      ...this.mapSummary(thread),
      messages: messageResult.rows.map((row) => this.mapMessage(row)),
    };
  }

  async saveTurnMetadata(threadId: string, userId: string, metadata: TurnMetadataInput): Promise<boolean> {
    const result = await this.run(
      `WITH owned_turn AS (
         SELECT messages.thread_id, messages.turn_index
         FROM aita_app.messages AS messages
         INNER JOIN aita_app.threads AS threads ON threads.id = messages.thread_id
         WHERE messages.thread_id = $1
           AND threads.user_id = $2
           AND messages.role = 'assistant'
         ORDER BY messages.turn_index DESC
         LIMIT 1
       )
       INSERT INTO aita_app.turn_metadata (
         thread_id, turn_index, routed_agents, genie_conversation_ids,
         generated_sql, latency_ms
       )
       SELECT thread_id, turn_index, $3::text[], $4::jsonb, $5::jsonb, $6
       FROM owned_turn
       ON CONFLICT (thread_id, turn_index) DO UPDATE SET
         routed_agents = EXCLUDED.routed_agents,
         genie_conversation_ids = EXCLUDED.genie_conversation_ids,
         generated_sql = EXCLUDED.generated_sql,
         latency_ms = EXCLUDED.latency_ms
       RETURNING turn_index`,
      [
        threadId,
        userId,
        metadata.routedAgents,
        JSON.stringify(metadata.genieConversationIds),
        JSON.stringify(metadata.generatedSql),
        metadata.latencyMs,
      ]
    );
    return result.rows.length > 0;
  }

  private mapSummary(row: Record<string, unknown>): HistorySummary {
    return {
      id: String(row.id),
      title: String(row.title),
      messageCount: Number(row.message_count),
      createdAt: this.toIso(row.created_at),
      updatedAt: this.toIso(row.updated_at),
    };
  }

  private mapMessage(row: Record<string, unknown>): HistoryMessage {
    const role = String(row.role);
    if (!['user', 'assistant', 'system', 'tool'].includes(role)) {
      throw new Error(`Unsupported history message role: ${role}`);
    }
    const metadata = this.mapMetadata(row);
    return {
      id: String(row.id),
      turnIndex: Number(row.turn_index),
      role: role as HistoryMessage['role'],
      content: String(row.content),
      createdAt: this.toIso(row.created_at),
      ...(metadata ? { metadata } : {}),
    };
  }

  private mapMetadata(row: Record<string, unknown>): HistoryTurnMetadata | null {
    if (!Array.isArray(row.routed_agents)) return null;
    const routedAgents = row.routed_agents.filter((value) => this.isAgentKey(value));
    const conversationValues = this.toRecord(row.genie_conversation_ids);
    const sqlValues = this.toRecord(row.generated_sql);
    const genieConversationIds: Partial<Record<AgentKey, string>> = {};
    const generatedSql: Partial<Record<AgentKey, SqlEvidence[]>> = {};
    for (const agent of AGENT_KEYS) {
      const conversationId = conversationValues[agent];
      if (typeof conversationId === 'string') genieConversationIds[agent] = conversationId;
      const statements = sqlValues[agent];
      if (Array.isArray(statements)) {
        generatedSql[agent] = statements.flatMap((statement) => {
          if (!this.isRecord(statement) || typeof statement.query !== 'string') return [];
          return [
            { query: statement.query, ...(typeof statement.title === 'string' ? { title: statement.title } : {}) },
          ];
        });
      }
    }
    return {
      routedAgents,
      genieConversationIds,
      generatedSql,
      ...(row.latency_ms === null || row.latency_ms === undefined ? {} : { latencyMs: Number(row.latency_ms) }),
    };
  }

  private isAgentKey(value: unknown): value is AgentKey {
    return typeof value === 'string' && AGENT_KEYS.some((agent) => agent === value);
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
  }

  private toRecord(value: unknown): Record<string, unknown> {
    if (this.isRecord(value)) return value;
    if (typeof value !== 'string') return {};
    try {
      const parsed: unknown = JSON.parse(value);
      return this.isRecord(parsed) ? parsed : {};
    } catch {
      return {};
    }
  }

  private toIso(value: unknown): string {
    const date = value instanceof Date ? value : new Date(String(value));
    if (Number.isNaN(date.getTime())) throw new Error('Invalid Lakebase timestamp');
    return date.toISOString();
  }

  private async purgeExpired(): Promise<void> {
    await this.run(`
      DELETE FROM aita_app.threads
      WHERE updated_at < NOW() - INTERVAL '30 days'
    `);
  }

  private run(text: string, params?: unknown[]) {
    if (!this.query) throw new Error('Lakebase history store is not initialized');
    return this.query(text, params);
  }
}
