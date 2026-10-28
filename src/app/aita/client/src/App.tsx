import { createBrowserRouter, NavLink, Outlet, RouterProvider } from 'react-router';
import { useEffect, useState } from 'react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  Badge,
  Button,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  Input,
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from '@databricks/appkit-ui/react';
import { Clock3, History, Menu, MessageSquareText, ShieldCheck, Users } from 'lucide-react';

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  `px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
    isActive
      ? 'bg-primary text-primary-foreground'
      : 'text-muted-foreground hover:bg-muted hover:text-foreground'
  }`;

const mobileNavLinkClass = ({ isActive }: { isActive: boolean }) =>
  `block px-3 py-2 rounded-md text-sm font-medium transition-colors ${
    isActive
      ? 'bg-primary text-primary-foreground'
      : 'text-muted-foreground hover:bg-muted hover:text-foreground'
  }`;

type NavLinkClassFn = (props: { isActive: boolean }) => string;

function NavLinks({ className, linkClass, onClick }: { className?: string; linkClass: NavLinkClassFn; onClick?: () => void }) {
  return (
    <nav className={className}>
      <NavLink to="/" end className={linkClass} onClick={onClick}>
        <MessageSquareText className="h-4 w-4 inline mr-1" />Chat
      </NavLink>
      <NavLink to="/watchlist" className={linkClass} onClick={onClick}>
        <Users className="h-4 w-4 inline mr-1" />Watchlist
      </NavLink>
      <NavLink to="/history" className={linkClass} onClick={onClick}>
        <History className="h-4 w-4 inline mr-1" />History
      </NavLink>
    </nav>
  );
}

function Layout() {
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/whoami')
      .then((response) => (response.ok ? response.json() : null))
      .then((identity: { email?: string | null } | null) =>
        setEmail(identity?.email ?? null),
      )
      .catch(() => setEmail(null));
  }, []);

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="border-b px-4 md:px-6 py-3 flex items-center gap-4">
        <h1 className="text-lg font-semibold text-foreground">Aita</h1>
        <Badge variant="outline">Owner-only development</Badge>
        <NavLinks className="hidden md:flex gap-1" linkClass={navLinkClass} />
        <Badge variant="secondary" className="ml-auto hidden md:inline-flex">
          {email ?? 'Signed in'}
        </Badge>
        <div className="md:hidden ml-auto">
          <Sheet open={mobileNavOpen} onOpenChange={setMobileNavOpen}>
            <Button variant="ghost" size="icon" onClick={() => setMobileNavOpen(true)}>
              <Menu className="h-5 w-5" />
              <span className="sr-only">Open navigation</span>
            </Button>
            <SheetContent side="left">
              <SheetHeader>
                <SheetTitle>Navigation</SheetTitle>
              </SheetHeader>
              <NavLinks className="flex flex-col gap-1" linkClass={mobileNavLinkClass} onClick={() => setMobileNavOpen(false)} />
            </SheetContent>
          </Sheet>
        </div>
      </header>

      <main className="flex-1 p-4 md:p-6">
        <Outlet />
      </main>
    </div>
  );
}

const router = createBrowserRouter([
  {
    element: <Layout />,
    children: [
      { path: '/', element: <HomePage /> },
      { path: '/watchlist', element: <WatchlistPage /> },
      { path: '/history', element: <HistoryPage /> },
    ],
  },
]);

export default function App() {
  return <RouterProvider router={router} />;
}

function HomePage() {
  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <div>
        <h2 className="text-3xl font-semibold text-foreground">Ask Aita</h2>
        <p className="text-muted-foreground mt-1">
          Governed HR analytics across workforce, talent, and recruiting.
        </p>
      </div>
      <Alert>
        <ShieldCheck className="h-4 w-4" />
        <AlertTitle>Foundation deployment</AlertTitle>
        <AlertDescription>
          Genie is configured on behalf of the signed-in user. Routing and
          synthesis arrive in Phase 13; this shell does not answer data questions.
        </AlertDescription>
      </Alert>
      <div className="grid gap-4 md:grid-cols-3">
        {['Workforce & Attrition', 'Talent & Performance', 'Recruiting'].map((name) => (
          <Card key={name}>
            <CardHeader>
              <CardTitle className="text-base">{name}</CardTitle>
              <CardDescription>OBO Genie Agent</CardDescription>
            </CardHeader>
          </Card>
        ))}
      </div>
      <Card>
        <CardHeader>
          <CardTitle>Chat</CardTitle>
          <CardDescription>
            The production chat surface will stream routed answers and show SQL per Agent.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <Input disabled placeholder="Routing is enabled in Phase 13" />
            <Button disabled>Ask</Button>
          </div>
          <p className="text-xs text-muted-foreground">
            AI-generated — verify answers against the generated SQL and source data.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

function WatchlistPage() {
  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <div>
        <h2 className="text-3xl font-semibold">Talent Watchlist</h2>
        <p className="text-muted-foreground mt-1">Low-latency reads from the existing Lakebase sync.</p>
      </div>
      <Alert>
        <Users className="h-4 w-4" />
        <AlertTitle>Human review required</AlertTitle>
        <AlertDescription>
          Watchlist flags prompt review and must never be treated as employment decisions.
        </AlertDescription>
      </Alert>
      <Card>
        <CardContent className="pt-6">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><Clock3 /></EmptyMedia>
              <EmptyTitle>Serving path connected</EmptyTitle>
              <EmptyDescription>
                Filtering, pagination, freshness, and parity checks arrive in Phase 14.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </CardContent>
      </Card>
    </div>
  );
}

function HistoryPage() {
  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <div>
        <h2 className="text-3xl font-semibold">History</h2>
        <p className="text-muted-foreground mt-1">Private conversation state retained for at most 30 days.</p>
      </div>
      <Card>
        <CardContent className="pt-6">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><History /></EmptyMedia>
              <EmptyTitle>No conversations yet</EmptyTitle>
              <EmptyDescription>
                Lakebase persistence and ownership isolation are wired. Replay and delete UI arrive in Phase 14.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </CardContent>
      </Card>
    </div>
  );
}
