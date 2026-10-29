import type { Application } from 'express';
import { z } from 'zod';
import {
  WATCHLIST_FLAGS,
  WATCHLIST_REVIEW_STATUSES,
  type WatchlistFlag,
  type WatchlistReviewStatus,
} from '../shared/app-state';
import type { LakebaseHistoryStore } from './history-store';
import type { LakebaseThreadStore } from './thread-store';
import { parseTurnMetadata } from './turn-metadata';
import type { LakebaseWatchlistStore } from './watchlist-store';

interface RouteStores {
  history: LakebaseHistoryStore;
  threads: LakebaseThreadStore;
  watchlist: LakebaseWatchlistStore;
}

const watchlistReviewSchema = z
  .object({
    status: z.enum(WATCHLIST_REVIEW_STATUSES),
    note: z.string().max(500).nullable().optional(),
  })
  .strict();

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
    const rawReviewStatus = queryText(req.query.reviewStatus, 80);
    const page = queryInteger(req.query.page, 1, 100_000);
    const pageSize = queryInteger(req.query.pageSize, 25, 100);
    if (
      (req.query.businessLine !== undefined && !businessLine) ||
      (req.query.flag !== undefined && !isWatchlistFlag(rawFlag)) ||
      (req.query.reviewStatus !== undefined && !isWatchlistReviewStatus(rawReviewStatus))
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
        ...(isWatchlistReviewStatus(rawReviewStatus) ? { reviewStatus: rawReviewStatus } : {}),
        page,
        pageSize,
      });
      res.json(result);
    } catch (error) {
      console.error('[aita] Failed to read watchlist', error);
      res.status(500).json({ error: 'Watchlist could not be loaded' });
    }
  });

  app.post('/api/watchlist/:employeeId/review', async (req, res) => {
    const reviewer = authenticatedUserId(req);
    if (!reviewer) {
      res.status(401).json({ error: 'Authenticated user is required' });
      return;
    }
    const employeeId = queryText(req.params.employeeId, 120);
    const parsed = watchlistReviewSchema.safeParse(req.body);
    if (!employeeId || !parsed.success) {
      res.status(400).json({ error: 'Invalid watchlist review' });
      return;
    }
    try {
      const review = await stores.watchlist.addReview(employeeId, reviewer, parsed.data);
      if (!review) {
        res.status(404).json({ error: 'Employee is not on the current watchlist' });
        return;
      }
      res.status(201).json({ review });
    } catch (error) {
      console.error('[aita] Failed to save watchlist review', error);
      res.status(500).json({ error: 'Watchlist review could not be saved' });
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

function isWatchlistReviewStatus(value: string | undefined): value is WatchlistReviewStatus {
  return value !== undefined && WATCHLIST_REVIEW_STATUSES.some((status) => status === value);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
