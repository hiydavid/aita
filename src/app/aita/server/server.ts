import { createApp, genie, lakebase, server } from '@databricks/appkit';
import { agents } from '@databricks/appkit/beta';
import { LakebaseThreadStore } from './thread-store';

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

const genieSpaces = {
  workforce_attrition: requiredEnv(
    'DATABRICKS_GENIE_SPACE_WORKFORCE_ATTRITION',
  ),
  talent_performance: requiredEnv(
    'DATABRICKS_GENIE_SPACE_TALENT_PERFORMANCE',
  ),
  recruiting: requiredEnv('DATABRICKS_GENIE_SPACE_RECRUITING'),
};
const threadStore = new LakebaseThreadStore();

interface WatchlistSummary {
  row_count: number;
  distinct_employee_id: number;
  null_employee_id: number;
  max_as_of_date: string | null;
}

await createApp({
  plugins: [
    agents({ threadStore }),
    genie({ spaces: genieSpaces }),
    lakebase(),
    server(),
  ],
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
    });
  },
});
