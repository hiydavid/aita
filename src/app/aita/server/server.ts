import { createApp, genie, lakebase, server } from '@databricks/appkit';
import { agents } from '@databricks/appkit/beta';
import { LakebaseHistoryStore, type LakebaseQuery } from './history-store';
import { registerRoutes } from './routes';
import { LakebaseThreadStore } from './thread-store';
import { LakebaseWatchlistStore } from './watchlist-store';

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
const historyStore = new LakebaseHistoryStore();
const watchlistSource = requiredEnv('LAKEBASE_SYNCED_TABLE');
const watchlistStore = new LakebaseWatchlistStore(watchlistSource);

await createApp({
  plugins: [agents({ threadStore }), genie({ spaces: genieSpaces }), lakebase(), server()],
  async onPluginsReady(appkit) {
    const lakebaseQuery: LakebaseQuery = async (text, params) => appkit.lakebase.query(text, params);
    await threadStore.initialize(lakebaseQuery);
    await historyStore.initialize(lakebaseQuery);
    await watchlistStore.initialize(lakebaseQuery);
    console.log('[aita] Watchlist source', watchlistSource);
    console.log('[aita] Watchlist parity', watchlistStore.getSummary());

    appkit.server.extend((app) => {
      registerRoutes(app, Object.keys(genieSpaces), {
        history: historyStore,
        threads: threadStore,
        watchlist: watchlistStore,
      });
    });
  },
});
