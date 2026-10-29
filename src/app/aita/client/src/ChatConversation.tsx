import type { FormEvent } from 'react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
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
  Skeleton,
  Textarea,
} from '@databricks/appkit-ui/react';
import { Bot, Database, Send } from 'lucide-react';
import { AGENT_DEFINITIONS, type RoutingCase } from '../../shared/routing';
import { AssistantAnswer, ChatEvidence, type ChatMessage } from './ChatAnswer';

interface ChatConversationProps {
  chatError: string | null;
  historyError: string | null;
  historyLoading: boolean;
  isStreaming: boolean;
  liveContent: string;
  liveEvidence: ChatMessage['evidence'];
  messages: ChatMessage[];
  metadataWarning: string | null;
  question: string;
  starters: RoutingCase[];
  onQuestionChange: (value: string) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
}

export function ChatConversation({
  chatError,
  historyError,
  historyLoading,
  isStreaming,
  liveContent,
  liveEvidence,
  messages,
  metadataWarning,
  question,
  starters,
  onQuestionChange,
  onSubmit,
}: ChatConversationProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Conversation</CardTitle>
        <CardDescription>Streamed answers retain follow-up context and expose SQL by Agent.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="h-[560px] space-y-4 overflow-y-auto rounded-md border p-4">
          {historyLoading && (
            <div className="space-y-2">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-28 w-3/4" />
            </div>
          )}
          {messages.length === 0 && !isStreaming && !historyLoading && (
            <Empty className="h-full">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <Bot />
                </EmptyMedia>
                <EmptyTitle>Ask a governed HR question</EmptyTitle>
                <EmptyDescription>Aita will route it and show the supporting Agent SQL.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
          {messages.map((item) =>
            item.role === 'user' ? (
              <div
                key={item.id}
                className="ml-auto max-w-2xl rounded-lg bg-primary px-4 py-3 text-sm text-primary-foreground"
              >
                {item.content}
              </div>
            ) : (
              <AssistantAnswer key={item.id} item={item} />
            )
          )}
          {isStreaming && (
            <Card className="max-w-4xl">
              <CardContent className="space-y-4 pt-6">
                {liveContent ? (
                  <div className="whitespace-pre-wrap text-sm leading-6">{liveContent}</div>
                ) : (
                  <div className="space-y-2">
                    <Skeleton className="h-4 w-3/4" />
                    <Skeleton className="h-4 w-1/2" />
                  </div>
                )}
                <ChatEvidence evidence={liveEvidence ?? []} />
                <p className="text-xs text-muted-foreground">Analyzing your data…</p>
              </CardContent>
            </Card>
          )}
        </div>

        {chatError && (
          <Alert variant="destructive">
            <AlertTitle>Chat failed</AlertTitle>
            <AlertDescription>{chatError}</AlertDescription>
          </Alert>
        )}
        {historyError && (
          <Alert variant="destructive">
            <AlertTitle>Conversation unavailable</AlertTitle>
            <AlertDescription>{historyError}</AlertDescription>
          </Alert>
        )}
        {metadataWarning && (
          <Alert>
            <Database className="h-4 w-4" />
            <AlertTitle>Partial persistence</AlertTitle>
            <AlertDescription>{metadataWarning}</AlertDescription>
          </Alert>
        )}

        <form onSubmit={onSubmit} className="space-y-3">
          <Textarea
            value={question}
            onChange={(event) => onQuestionChange(event.target.value)}
            placeholder="Ask about workforce, talent, recruiting, or a cross-domain question"
            disabled={isStreaming || historyLoading}
            rows={3}
          />
          <div className="flex flex-wrap items-center gap-2">
            <Button type="submit" disabled={isStreaming || historyLoading || !question.trim()}>
              <Send className="h-4 w-4" /> Ask
            </Button>
            {starters.map((starter) => (
              <Button
                key={starter.id}
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => onQuestionChange(starter.question)}
                disabled={isStreaming}
              >
                {AGENT_DEFINITIONS[starter.expectedAgent].title}
              </Button>
            ))}
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
