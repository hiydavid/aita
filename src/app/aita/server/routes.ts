import type { Application } from 'express';
import { WATCHLIST_FLAGS, type WatchlistFlag } from '../shared/app-state';
import { AGENT_KEYS, type AgentKey, type SqlEvidence, type TurnMetadataInput } from '../shared/routing';
import type { LakebaseHistoryStore } from './history-store';
import type { LakebaseThreadStore } from './thread-store';
import type { LakebaseWatchlistStore } from './watchlist-store';

interface RouteStores {
  history: LakebaseHistoryStore;
  threads: LakebaseThreadStore;
  watchlist: LakebaseWatchlistStore;
}

export function registerRoutes(app: Application, genieAliases: string[], stores: RouteStores): void {
  app.get('/api/whoami', (req, res) => {
    res.json({
      email: req.header('x-forwarded-email') ?? null,
      user: req.header('x-forwarded-user') ?? null,
    });
  });

  app.get('/api/foundation', (_req, res) => {
    res.json({
      deployment: 'owner-only',
      genieAliases,
      genieExecution: 'on-behalf-of-user',
      lakebaseExecution: 'service-principal',
      threadStore: 'lakebase',
      watchlist: stores.watchlist.getSummary(),
    });
  });

  app.get('/api/watchlist', async (req, res) => {
    if (!authenticatedUserId(req)) {
      res.status(401).json({ error: 'Authenticated user is required' });
      return;
    }
    const businessLine = queryText(req.query.businessLine, 120);
    const rawFlag = queryText(req.query.flag, 80);
    const page = queryInteger(req.query.page, 1, 100_000);
    const pageSize = queryInteger(req.query.pageSize, 25, 100);
    if (
      (req.query.businessLine !== undefined && !businessLine) ||
      (req.query.flag !== undefined && !isWatchlistFlag(rawFlag))
    ) {
      res.status(400).json({ error: 'Invalid watchlist filter' });
      return;
    }
    if (page === null || pageSize === null) {
      res.status(400).json({ error: 'Invalid pagination' });
      return;
    }
    try {
      const result = await stores.watchlist.list({
        ...(businessLine ? { businessLine } : {}),
        ...(isWatchlistFlag(rawFlag) ? { flag: rawFlag } : {}),
        page,
        pageSize,
      });
      res.json(result);
    } catch (error) {
      console.error('[aita] Failed to read watchlist', error);
      res.status(500).json({ error: 'Watchlist could not be loaded' });
    }
  });

  app.get('/api/history', async (req, res) => {
    const userId = authenticatedUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authenticated user is required' });
      return;
    }
    try {
      res.json({ conversations: await stores.history.list(userId), retentionDays: 30 });
    } catch (error) {
      console.error('[aita] Failed to list history', error);
      res.status(500).json({ error: 'History could not be loaded' });
    }
  });

  app.get('/api/history/:threadId', async (req, res) => {
    const userId = authenticatedUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authenticated user is required' });
      return;
    }
    if (!isUuid(req.params.threadId)) {
      res.status(400).json({ error: 'Invalid conversation ID' });
      return;
    }
    try {
      const conversation = await stores.history.get(req.params.threadId, userId);
      if (!conversation) {
        res.status(404).json({ error: 'Conversation not found' });
        return;
      }
      res.json(conversation);
    } catch (error) {
      console.error('[aita] Failed to read history', error);
      res.status(500).json({ error: 'Conversation could not be loaded' });
    }
  });

  app.delete('/api/history/:threadId', async (req, res) => {
    const userId = authenticatedUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authenticated user is required' });
      return;
    }
    if (!isUuid(req.params.threadId)) {
      res.status(400).json({ error: 'Invalid conversation ID' });
      return;
    }
    try {
      if (!(await stores.threads.delete(req.params.threadId, userId))) {
        res.status(404).json({ error: 'Conversation not found' });
        return;
      }
      res.status(204).end();
    } catch (error) {
      console.error('[aita] Failed to delete history', error);
      res.status(500).json({ error: 'Conversation could not be deleted' });
    }
  });

  app.post('/api/threads/:threadId/metadata', async (req, res) => {
    const userId = authenticatedUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authenticated user is required' });
      return;
    }
    if (!isUuid(req.params.threadId)) {
      res.status(400).json({ error: 'Invalid conversation ID' });
      return;
    }
    const metadata = parseTurnMetadata(req.body);
    if (!metadata) {
      res.status(400).json({ error: 'Invalid turn metadata' });
      return;
    }
    try {
      const saved = await stores.history.saveTurnMetadata(req.params.threadId, userId, metadata);
      if (!saved) {
        res.status(404).json({ error: 'Thread or assistant turn not found' });
        return;
      }
      res.status(204).end();
    } catch (error) {
      console.error('[aita] Failed to save turn metadata', error);
      res.status(500).json({ error: 'Turn metadata could not be saved' });
    }
  });
}

function authenticatedUserId(request: { header(name: string): string | undefined }): string | null {
  return request.header('x-forwarded-user')?.trim() || null;
}

function queryText(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== 'string') return undefined;
  const result = value.trim();
  return result && result.length <= maxLength ? result : undefined;
}

function queryInteger(value: unknown, fallback: number, maximum: number): number | null {
  if (value === undefined) return fallback;
  if (typeof value !== 'string' || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 1 && parsed <= maximum ? parsed : null;
}

function isWatchlistFlag(value: string | undefined): value is WatchlistFlag {
  return value !== undefined && WATCHLIST_FLAGS.some((flag) => flag === value);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isAgentKey(value: unknown): value is AgentKey {
  return typeof value === 'string' && AGENT_KEYS.some((agent) => agent === value);
}

function parseTurnMetadata(value: unknown): TurnMetadataInput | null {
  if (!isRecord(value)) return null;
  const routedAgents = value.routedAgents;
  const latencyMs = value.latencyMs;
  if (
    !Array.isArray(routedAgents) ||
    routedAgents.length > AGENT_KEYS.length ||
    !routedAgents.every(isAgentKey) ||
    new Set(routedAgents).size !== routedAgents.length ||
    typeof latencyMs !== 'number' ||
    !Number.isInteger(latencyMs) ||
    latencyMs < 0 ||
    latencyMs > 600_000
  ) {
    return null;
  }
  if (!isRecord(value.genieConversationIds) || !isRecord(value.generatedSql)) return null;

  const genieConversationIds: Partial<Record<AgentKey, string>> = {};
  const generatedSql: Partial<Record<AgentKey, SqlEvidence[]>> = {};
  for (const agent of AGENT_KEYS) {
    const conversationId = value.genieConversationIds[agent];
    if (conversationId !== undefined) {
      if (typeof conversationId !== 'string' || conversationId.length > 128) return null;
      genieConversationIds[agent] = conversationId;
    }
    const rawStatements = value.generatedSql[agent];
    if (rawStatements === undefined) continue;
    if (!Array.isArray(rawStatements) || rawStatements.length > 20) return null;
    const statements: SqlEvidence[] = [];
    for (const rawStatement of rawStatements) {
      if (!isRecord(rawStatement) || typeof rawStatement.query !== 'string' || rawStatement.query.length > 50_000) {
        return null;
      }
      if (rawStatement.title !== undefined && typeof rawStatement.title !== 'string') return null;
      statements.push({
        query: rawStatement.query,
        ...(rawStatement.title ? { title: rawStatement.title.slice(0, 500) } : {}),
      });
    }
    generatedSql[agent] = statements;
  }
  return { routedAgents, genieConversationIds, generatedSql, latencyMs };
}
