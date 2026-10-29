import { createApp, genie, lakebase, server } from '@databricks/appkit';
import { agents } from '@databricks/appkit/beta';
import { LakebaseThreadStore } from './thread-store';
import { AGENT_KEYS, type AgentKey, type SqlEvidence, type TurnMetadataInput } from '../shared/routing';

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

const genieSpaces = {
  workforce_attrition: requiredEnv('DATABRICKS_GENIE_SPACE_WORKFORCE_ATTRITION'),
  talent_performance: requiredEnv('DATABRICKS_GENIE_SPACE_TALENT_PERFORMANCE'),
  recruiting: requiredEnv('DATABRICKS_GENIE_SPACE_RECRUITING'),
};
const threadStore = new LakebaseThreadStore();

interface WatchlistSummary {
  row_count: number;
  distinct_employee_id: number;
  null_employee_id: number;
  max_as_of_date: string | null;
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

  const rawConversationIds = value.genieConversationIds;
  const rawGeneratedSql = value.generatedSql;
  if (!isRecord(rawConversationIds) || !isRecord(rawGeneratedSql)) return null;

  const genieConversationIds: Partial<Record<AgentKey, string>> = {};
  const generatedSql: Partial<Record<AgentKey, SqlEvidence[]>> = {};
  for (const agent of AGENT_KEYS) {
    const conversationId = rawConversationIds[agent];
    if (conversationId !== undefined) {
      if (typeof conversationId !== 'string' || conversationId.length > 128) {
        return null;
      }
      genieConversationIds[agent] = conversationId;
    }

    const rawStatements = rawGeneratedSql[agent];
    if (rawStatements === undefined) continue;
    if (!Array.isArray(rawStatements) || rawStatements.length > 20) return null;
    const statements: SqlEvidence[] = [];
    for (const rawStatement of rawStatements) {
      if (!isRecord(rawStatement) || typeof rawStatement.query !== 'string') {
        return null;
      }
      if (rawStatement.query.length > 50_000) return null;
      const title = rawStatement.title;
      if (title !== undefined && typeof title !== 'string') return null;
      statements.push({
        query: rawStatement.query,
        ...(title ? { title: title.slice(0, 500) } : {}),
      });
    }
    generatedSql[agent] = statements;
  }

  return {
    routedAgents,
    genieConversationIds,
    generatedSql,
    latencyMs,
  };
}

await createApp({
  plugins: [agents({ threadStore }), genie({ spaces: genieSpaces }), lakebase(), server()],
  async onPluginsReady(appkit) {
    await threadStore.initialize(appkit.lakebase.query.bind(appkit.lakebase));
    const watchlistResult = await appkit.lakebase.query<WatchlistSummary>(`
      SELECT COUNT(*)::integer AS row_count,
             COUNT(DISTINCT employee_id)::integer AS distinct_employee_id,
             COUNT(*) FILTER (WHERE employee_id IS NULL)::integer AS null_employee_id,
             MAX(as_of_date)::text AS max_as_of_date
      FROM aita_gold.talent_watchlist_serving
    `);
    const watchlistSummary = watchlistResult.rows[0] ?? null;
    console.log('[aita] Watchlist parity', watchlistSummary);

    appkit.server.extend((app) => {
      app.get('/api/whoami', (req, res) => {
        res.json({
          email: req.header('x-forwarded-email') ?? null,
          user: req.header('x-forwarded-user') ?? null,
        });
      });

      app.get('/api/foundation', (_req, res) => {
        res.json({
          deployment: 'owner-only',
          genieAliases: Object.keys(genieSpaces),
          genieExecution: 'on-behalf-of-user',
          lakebaseExecution: 'service-principal',
          threadStore: 'lakebase',
          watchlist: watchlistSummary,
        });
      });

      app.post('/api/threads/:threadId/metadata', async (req, res) => {
        const userId = req.header('x-forwarded-user')?.trim();
        if (!userId) {
          res.status(401).json({ error: 'Authenticated user is required' });
          return;
        }
        const metadata = parseTurnMetadata(req.body);
        if (!metadata) {
          res.status(400).json({ error: 'Invalid turn metadata' });
          return;
        }
        try {
          const saved = await threadStore.saveTurnMetadata(req.params.threadId, userId, metadata);
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
    });
  },
});
