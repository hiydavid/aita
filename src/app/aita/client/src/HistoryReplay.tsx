import {
  Alert,
  AlertDescription,
  AlertTitle,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Skeleton,
} from '@databricks/appkit-ui/react';
import { MessageSquareText } from 'lucide-react';
import type { HistoryDetail, HistoryMessage } from '../../shared/app-state';
import { AssistantAnswer } from './ChatAnswer';
import { toChatMessage } from './history-chat';

export function HistoryReplay({
  conversation,
  error,
  loading,
  onContinue,
}: {
  conversation: HistoryDetail | null;
  error: string | null;
  loading: boolean;
  onContinue: (threadId: string) => void;
}) {
  if (!loading && !error && !conversation) return null;
  return (
    <Card>
      <CardHeader>
        <CardTitle>{conversation?.title ?? 'Conversation replay'}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {loading && <Skeleton className="h-40 w-full" />}
        {error && (
          <Alert variant="destructive">
            <AlertTitle>Replay unavailable</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        {!loading && conversation && (
          <>
            {conversation.messages.map((message) => (
              <ReplayMessage key={message.id} message={message} />
            ))}
            <Button onClick={() => onContinue(conversation.id)}>
              <MessageSquareText className="h-4 w-4" /> Continue this conversation
            </Button>
          </>
        )}
      </CardContent>
    </Card>
  );
}

function ReplayMessage({ message }: { message: HistoryMessage }) {
  const item = toChatMessage(message);
  if (!item) return null;
  if (item.role === 'user') {
    return (
      <div className="ml-auto max-w-2xl rounded-lg bg-primary px-4 py-3 text-sm text-primary-foreground">
        {item.content}
      </div>
    );
  }
  return <AssistantAnswer item={item} />;
}
