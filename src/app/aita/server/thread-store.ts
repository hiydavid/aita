import { randomUUID } from 'node:crypto';
import type { Message, Thread, ThreadStore } from '@databricks/appkit/beta';

type Query = (text: string, params?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;

const RETENTION_SQL = `
  DELETE FROM aita_app.threads
  WHERE updated_at < NOW() - INTERVAL '30 days'
`;

export class LakebaseThreadStore implements ThreadStore {
  private query?: Query;
  private liveThreads = new Map<string, Thread>();

  async initialize(query: Query): Promise<void> {
    this.query = query;
    await query('CREATE SCHEMA IF NOT EXISTS aita_app');
    await query(`
      CREATE TABLE IF NOT EXISTS aita_app.threads (
        id UUID PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT 'New conversation',
        next_turn_index INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await query(`
      CREATE INDEX IF NOT EXISTS threads_user_updated_idx
      ON aita_app.threads (user_id, updated_at DESC)
    `);
    await query(`
      CREATE TABLE IF NOT EXISTS aita_app.messages (
        id UUID PRIMARY KEY,
        thread_id UUID NOT NULL REFERENCES aita_app.threads(id) ON DELETE CASCADE,
        turn_index INTEGER NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'tool')),
        content TEXT NOT NULL,
        tool_call_id TEXT,
        tool_calls JSONB,
        created_at TIMESTAMPTZ NOT NULL,
        UNIQUE (thread_id, turn_index)
      )
    `);
    await this.purgeExpired();
  }

  async create(userId: string): Promise<Thread> {
    await this.purgeExpired();
    const id = randomUUID();
    const result = await this.run(
      `INSERT INTO aita_app.threads (id, user_id)
       VALUES ($1, $2)
       RETURNING id, user_id, created_at, updated_at`,
      [id, userId]
    );
    return this.rememberThread(this.mapThread(result.rows[0], []));
  }

  async get(threadId: string, userId: string): Promise<Thread | null> {
    await this.purgeExpired();
    const threads = await this.loadThreads(userId, threadId);
    return threads[0] ?? null;
  }

  async list(userId: string): Promise<Thread[]> {
    await this.purgeExpired();
    return this.loadThreads(userId);
  }

  async addMessage(threadId: string, userId: string, message: Message): Promise<void> {
    await this.purgeExpired();
    const result = await this.run(
      `WITH next_turn AS (
       UPDATE aita_app.threads
         SET next_turn_index = next_turn_index + 1,
             title = CASE
               WHEN next_turn_index = 0 AND $4 = 'user' THEN LEFT($5, 120)
               ELSE title
             END,
             updated_at = NOW()
         WHERE id = $1 AND user_id = $2
         RETURNING next_turn_index - 1 AS turn_index
       )
       INSERT INTO aita_app.messages (
         id, thread_id, turn_index, role, content, tool_call_id, tool_calls, created_at
       )
       SELECT $3, $1, turn_index, $4, $5, $6, $7::jsonb, $8
       FROM next_turn
       RETURNING id`,
      [
        threadId,
        userId,
        message.id,
        message.role,
        message.content,
        message.toolCallId ?? null,
        message.toolCalls ? JSON.stringify(message.toolCalls) : null,
        message.createdAt,
      ]
    );
    if (result.rows.length === 0) {
      throw new Error(`Thread ${threadId} not found`);
    }
    this.liveThreads.get(threadId)?.messages.push(message);
  }

  async delete(threadId: string, userId: string): Promise<boolean> {
    const result = await this.run(
      `DELETE FROM aita_app.threads
       WHERE id = $1 AND user_id = $2
       RETURNING id`,
      [threadId, userId]
    );
    if (result.rows.length > 0) this.liveThreads.delete(threadId);
    return result.rows.length > 0;
  }

  private async loadThreads(userId: string, threadId?: string): Promise<Thread[]> {
    const threadResult = await this.run(
      `SELECT id, user_id, created_at, updated_at
       FROM aita_app.threads
       WHERE user_id = $1 AND ($2::uuid IS NULL OR id = $2::uuid)
       ORDER BY updated_at DESC`,
      [userId, threadId ?? null]
    );
    if (threadResult.rows.length === 0) return [];

    const ids = threadResult.rows.map((row) => String(row.id));
    const messageResult = await this.run(
      `SELECT id, thread_id, role, content, tool_call_id, tool_calls, created_at
       FROM aita_app.messages
       WHERE thread_id = ANY($1::uuid[])
       ORDER BY thread_id, turn_index`,
      [ids]
    );
    const messages = new Map<string, Message[]>();
    for (const row of messageResult.rows) {
      const id = String(row.thread_id);
      const current = messages.get(id) ?? [];
      current.push(this.mapMessage(row));
      messages.set(id, current);
    }
    return threadResult.rows.map((row) => this.rememberThread(this.mapThread(row, messages.get(String(row.id)) ?? [])));
  }

  private rememberThread(thread: Thread): Thread {
    const current = this.liveThreads.get(thread.id);
    if (current) return Object.assign(current, thread);
    this.liveThreads.set(thread.id, thread);
    return thread;
  }

  private mapThread(row: Record<string, unknown> | undefined, messages: Message[]): Thread {
    if (!row) throw new Error('Lakebase did not return a thread row');
    return {
      id: String(row.id),
      userId: String(row.user_id),
      messages,
      createdAt: this.toDate(row.created_at),
      updatedAt: this.toDate(row.updated_at),
    };
  }

  private mapMessage(row: Record<string, unknown>): Message {
    const role = String(row.role);
    if (!['user', 'assistant', 'system', 'tool'].includes(role)) {
      throw new Error(`Unsupported persisted message role: ${role}`);
    }
    return {
      id: String(row.id),
      role: role as Message['role'],
      content: String(row.content),
      toolCallId: typeof row.tool_call_id === 'string' ? row.tool_call_id : undefined,
      toolCalls: this.mapToolCalls(row.tool_calls),
      createdAt: this.toDate(row.created_at),
    };
  }

  private mapToolCalls(value: unknown): Message['toolCalls'] {
    if (!Array.isArray(value)) return undefined;
    return value.flatMap((entry) => {
      if (!entry || typeof entry !== 'object') return [];
      const call = entry as Record<string, unknown>;
      if (typeof call.id !== 'string' || typeof call.name !== 'string') return [];
      return [
        {
          id: call.id,
          name: call.name,
          args: call.args,
          thoughtSignature: typeof call.thoughtSignature === 'string' ? call.thoughtSignature : undefined,
        },
      ];
    });
  }

  private toDate(value: unknown): Date {
    const date = value instanceof Date ? value : new Date(String(value));
    if (Number.isNaN(date.getTime())) throw new Error('Invalid Lakebase timestamp');
    return date;
  }

  private async purgeExpired(): Promise<void> {
    await this.run(RETENTION_SQL);
  }

  private run(text: string, params?: unknown[]) {
    if (!this.query) throw new Error('Lakebase thread store is not initialized');
    return this.query(text, params);
  }
}
