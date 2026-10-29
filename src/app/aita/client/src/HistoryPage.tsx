import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import {
  Alert,
  AlertDescription,
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
  AlertTitle,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import { History, MessageSquareText, Play, RefreshCw, ShieldCheck, Trash2 } from 'lucide-react';
import type { HistoryDetail, HistoryListResponse } from '../../shared/app-state';
import { HistoryReplay } from './HistoryReplay';

export function HistoryPage() {
  const navigate = useNavigate();
  const [history, setHistory] = useState<HistoryListResponse | null>(null);
  const [selected, setSelected] = useState<HistoryDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [detailLoading, setDetailLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const loadHistory = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch('/api/history');
      if (!response.ok)
        throw new Error(response.status === 401 ? 'Your session is not authorized.' : 'History failed.');
      setHistory((await response.json()) as HistoryListResponse);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'History could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadHistory();
  }, [loadHistory]);

  async function replay(threadId: string) {
    setDetailLoading(true);
    setDetailError(null);
    try {
      const response = await fetch(`/api/history/${encodeURIComponent(threadId)}`);
      if (!response.ok) throw new Error(response.status === 404 ? 'Conversation not found.' : 'Replay failed.');
      setSelected((await response.json()) as HistoryDetail);
    } catch (loadError) {
      setDetailError(loadError instanceof Error ? loadError.message : 'Conversation could not be replayed.');
    } finally {
      setDetailLoading(false);
    }
  }

  async function deleteConversation(threadId: string) {
    setDeletingId(threadId);
    setError(null);
    try {
      const response = await fetch(`/api/history/${encodeURIComponent(threadId)}`, { method: 'DELETE' });
      if (!response.ok) throw new Error(response.status === 404 ? 'Conversation not found.' : 'Delete failed.');
      if (selected?.id === threadId) setSelected(null);
      await loadHistory();
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Conversation could not be deleted.');
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div>
        <h2 className="text-3xl font-semibold">History</h2>
        <p className="mt-1 text-muted-foreground">
          Replay, continue, or permanently delete your private conversations.
        </p>
      </div>

      <Alert>
        <ShieldCheck className="h-4 w-4" />
        <AlertTitle>User-scoped storage</AlertTitle>
        <AlertDescription>
          The server derives your identity from Databricks and retains conversations for at most{' '}
          {history?.retentionDays ?? 30} days.
        </AlertDescription>
      </Alert>

      {error && (
        <Alert variant="destructive">
          <AlertTitle>History unavailable</AlertTitle>
          <AlertDescription className="flex items-center justify-between gap-3">
            <span>{error}</span>
            <Button size="sm" variant="outline" onClick={() => void loadHistory()}>
              <RefreshCw className="h-4 w-4" /> Retry
            </Button>
          </AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Your conversations</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="space-y-3">
              {[1, 2, 3].map((item) => (
                <Skeleton key={item} className="h-12 w-full" />
              ))}
            </div>
          ) : history?.conversations.length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Conversation</TableHead>
                  <TableHead>Updated</TableHead>
                  <TableHead>Messages</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {history.conversations.map((conversation) => (
                  <TableRow key={conversation.id}>
                    <TableCell className="max-w-md font-medium">{conversation.title}</TableCell>
                    <TableCell>{formatTimestamp(conversation.updatedAt)}</TableCell>
                    <TableCell>{conversation.messageCount}</TableCell>
                    <TableCell>
                      <div className="flex justify-end gap-2">
                        <Button size="sm" variant="outline" onClick={() => void replay(conversation.id)}>
                          <Play className="h-4 w-4" /> Replay
                        </Button>
                        <Button
                          size="sm"
                          onClick={() => void navigate(`/?thread=${encodeURIComponent(conversation.id)}`)}
                        >
                          <MessageSquareText className="h-4 w-4" /> Continue
                        </Button>
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button size="icon" variant="ghost" disabled={deletingId === conversation.id}>
                              <Trash2 className="h-4 w-4" />
                              <span className="sr-only">Delete conversation</span>
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Delete this conversation?</AlertDialogTitle>
                              <AlertDialogDescription>
                                This permanently removes the thread, its messages, and saved routing evidence.
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancel</AlertDialogCancel>
                              <AlertDialogAction onClick={() => void deleteConversation(conversation.id)}>
                                Delete
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <History />
                </EmptyMedia>
                <EmptyTitle>No conversations yet</EmptyTitle>
                <EmptyDescription>Ask Aita a question and the conversation will appear here.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
        </CardContent>
      </Card>

      <HistoryReplay
        conversation={selected}
        error={detailError}
        loading={detailLoading}
        onContinue={(threadId) => void navigate(`/?thread=${encodeURIComponent(threadId)}`)}
      />
    </div>
  );
}

function formatTimestamp(value: string): string {
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}
