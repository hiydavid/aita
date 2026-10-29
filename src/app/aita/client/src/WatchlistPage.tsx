import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import { Alert, AlertDescription, AlertTitle, Button } from '@databricks/appkit-ui/react';
import { AlertTriangle, RefreshCw, Users } from 'lucide-react';
import type { WatchlistResponse } from '../../shared/app-state';
import { ALL_FILTERS, WatchlistTable } from './WatchlistTable';

export function WatchlistPage() {
  const navigate = useNavigate();
  const [businessLine, setBusinessLine] = useState(ALL_FILTERS);
  const [flag, setFlag] = useState(ALL_FILTERS);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<WatchlistResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadWatchlist = useCallback(
    async (signal?: AbortSignal) => {
      setLoading(true);
      setError(null);
      const parameters = new URLSearchParams({ page: String(page), pageSize: '25' });
      if (businessLine !== ALL_FILTERS) parameters.set('businessLine', businessLine);
      if (flag !== ALL_FILTERS) parameters.set('flag', flag);
      try {
        const response = await fetch(`/api/watchlist?${parameters}`, { signal });
        if (!response.ok) {
          throw new Error(response.status === 401 ? 'Your session is not authorized.' : 'Watchlist request failed.');
        }
        setData((await response.json()) as WatchlistResponse);
      } catch (loadError) {
        if (loadError instanceof DOMException && loadError.name === 'AbortError') return;
        setError(loadError instanceof Error ? loadError.message : 'Watchlist could not be loaded.');
      } finally {
        if (!signal?.aborted) setLoading(false);
      }
    },
    [businessLine, flag, page]
  );

  useEffect(() => {
    const controller = new AbortController();
    void loadWatchlist(controller.signal);
    return () => controller.abort();
  }, [loadWatchlist]);

  function resetFilters() {
    setBusinessLine(ALL_FILTERS);
    setFlag(ALL_FILTERS);
    setPage(1);
  }

  function askAita(employeeId: string) {
    const prompt = `Explain why employee ${employeeId} appears on the talent watchlist and summarize the supporting governed signals.`;
    void navigate(`/?prompt=${encodeURIComponent(prompt)}`);
  }

  const showingPartial = Boolean(error && data);

  return (
    <div className="mx-auto max-w-7xl space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-3xl font-semibold">Talent Watchlist</h2>
          <p className="mt-1 text-muted-foreground">Read-only, low-latency signals from the Lakebase synced table.</p>
        </div>
        <div className="text-right text-sm text-muted-foreground">
          <div>Source as of {data?.freshness.asOfDate ?? 'unknown'}</div>
          <div>{data ? `${data.parity.rowCount.toLocaleString()} synced employees` : 'Checking freshness…'}</div>
        </div>
      </div>

      <Alert>
        <Users className="h-4 w-4" />
        <AlertTitle>Human review required</AlertTitle>
        <AlertDescription>
          These rule-based signals prompt review and must never be treated as employment decisions.
        </AlertDescription>
      </Alert>

      {(data?.freshness.stale || !data?.parity.passed) && data && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>Serving data needs review</AlertTitle>
          <AlertDescription>
            {data.freshness.stale
              ? 'The watchlist source is older than the expected refresh window.'
              : 'The synced row count, employee key uniqueness, or freshness check did not pass.'}
          </AlertDescription>
        </Alert>
      )}

      {error && (
        <Alert variant={showingPartial ? 'default' : 'destructive'}>
          <AlertTitle>{showingPartial ? 'Showing previously loaded data' : 'Watchlist unavailable'}</AlertTitle>
          <AlertDescription className="flex items-center justify-between gap-3">
            <span>{error}</span>
            <Button size="sm" variant="outline" onClick={() => void loadWatchlist()}>
              <RefreshCw className="h-4 w-4" /> Retry
            </Button>
          </AlertDescription>
        </Alert>
      )}

      <WatchlistTable
        businessLine={businessLine}
        data={data}
        error={error}
        flag={flag}
        loading={loading}
        page={page}
        onAskAita={askAita}
        onBusinessLineChange={(value) => {
          setBusinessLine(value);
          setPage(1);
        }}
        onFlagChange={(value) => {
          setFlag(value);
          setPage(1);
        }}
        onPageChange={setPage}
        onReset={resetFilters}
      />
    </div>
  );
}
