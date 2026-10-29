import { createBrowserRouter, NavLink, Outlet, RouterProvider } from 'react-router';
import { useEffect, useState } from 'react';
import { Badge, Button, Sheet, SheetContent, SheetHeader, SheetTitle } from '@databricks/appkit-ui/react';
import { History, Menu, MessageSquareText, Users } from 'lucide-react';
import { ChatPage } from './ChatPage';
import { HistoryPage } from './HistoryPage';
import { WatchlistPage } from './WatchlistPage';

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  `px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
    isActive ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-muted hover:text-foreground'
  }`;

const mobileNavLinkClass = ({ isActive }: { isActive: boolean }) =>
  `block px-3 py-2 rounded-md text-sm font-medium transition-colors ${
    isActive ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-muted hover:text-foreground'
  }`;

type NavLinkClassFn = (props: { isActive: boolean }) => string;

function NavLinks({
  className,
  linkClass,
  onClick,
}: {
  className?: string;
  linkClass: NavLinkClassFn;
  onClick?: () => void;
}) {
  return (
    <nav className={className}>
      <NavLink to="/" end className={linkClass} onClick={onClick}>
        <MessageSquareText className="h-4 w-4 inline mr-1" />
        Chat
      </NavLink>
      <NavLink to="/watchlist" className={linkClass} onClick={onClick}>
        <Users className="h-4 w-4 inline mr-1" />
        Watchlist
      </NavLink>
      <NavLink to="/history" className={linkClass} onClick={onClick}>
        <History className="h-4 w-4 inline mr-1" />
        History
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
      .then((identity: { email?: string | null } | null) => setEmail(identity?.email ?? null))
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
              <NavLinks
                className="flex flex-col gap-1"
                linkClass={mobileNavLinkClass}
                onClick={() => setMobileNavOpen(false)}
              />
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
      { path: '/', element: <ChatPage /> },
      { path: '/watchlist', element: <WatchlistPage /> },
      { path: '/history', element: <HistoryPage /> },
    ],
  },
]);

export default function App() {
  return <RouterProvider router={router} />;
}
