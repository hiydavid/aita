import { type FormEvent, useRef, useState } from 'react';
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
  useAgentChat,
} from '@databricks/appkit-ui/react';
import { Bot, Database, Plus, Send, ShieldCheck } from 'lucide-react';
import { AGENT_DEFINITIONS, AGENT_KEYS, ROUTING_CASES, type RoutingCase } from '../../shared/routing';
import { AssistantAnswer, ChatEvidence, type ChatMessage } from './ChatAnswer';
import {
  captureAgentEvent,
  createEvidenceCollector,
  evidenceSnapshot,
  toTurnMetadata,
  visibleAssistantContent,
} from './chat-evidence';

const STARTERS = AGENT_KEYS.map((agent) =>
  ROUTING_CASES.find((routingCase) => routingCase.expectedAgent === agent)
).filter((routingCase): routingCase is RoutingCase => Boolean(routingCase));

export function ChatPage() {
  const [question, setQuestion] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [liveEvidence, setLiveEvidence] = useState<ChatMessage['evidence']>([]);
  const [metadataWarning, setMetadataWarning] = useState<string | null>(null);
  const collectorRef = useRef(createEvidenceCollector());
  const rawContentRef = useRef('');
  const threadIdRef = useRef<string | null>(null);

  const { content, isStreaming, error, send, reset } = useAgentChat({
    agent: 'aita',
    onEvent(event) {
      if (event.type === 'response.output_text.delta' && typeof event.delta === 'string') {
        rawContentRef.current += event.delta;
      }
      if (event.type === 'appkit.metadata' && typeof event.data?.threadId === 'string') {
        threadIdRef.current = event.data.threadId;
      }
      if (captureAgentEvent(event, collectorRef.current)) {
        setLiveEvidence(evidenceSnapshot(collectorRef.current));
      }
    },
  });

  async function ask(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const prompt = question.trim();
    if (!prompt || isStreaming) return;
    setQuestion('');
    setMetadataWarning(null);
    setMessages((current) => [...current, { id: crypto.randomUUID(), role: 'user', content: prompt }]);
    collectorRef.current = createEvidenceCollector();
    rawContentRef.current = '';
    setLiveEvidence([]);
    const startedAt = performance.now();
    await send(prompt);
    const latencyMs = Math.round(performance.now() - startedAt);
    const evidence = evidenceSnapshot(collectorRef.current);
    const answer = visibleAssistantContent(rawContentRef.current);
    if (answer) {
      setMessages((current) => [
        ...current,
        {
          id: crypto.randomUUID(),
          role: 'assistant',
          content: answer,
          evidence,
          latencyMs,
        },
      ]);
    }
    const activeThreadId = threadIdRef.current;
    if (activeThreadId && answer) {
      try {
        const response = await fetch(`/api/threads/${encodeURIComponent(activeThreadId)}/metadata`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(toTurnMetadata(evidence, latencyMs)),
        });
        if (!response.ok) throw new Error('metadata request failed');
      } catch {
        setMetadataWarning('The answer is available, but its routing metadata was not saved.');
      }
    }
  }

  function newConversation() {
    reset();
    threadIdRef.current = null;
    rawContentRef.current = '';
    collectorRef.current = createEvidenceCollector();
    setMessages([]);
    setLiveEvidence([]);
    setMetadataWarning(null);
  }

  const liveContent = visibleAssistantContent(content);

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-3xl font-semibold">Ask Aita</h2>
          <p className="mt-1 text-muted-foreground">Governed HR analytics across workforce, talent, and recruiting.</p>
        </div>
        <Button variant="outline" onClick={newConversation}>
          <Plus className="h-4 w-4" /> New conversation
        </Button>
      </div>

      <Alert>
        <ShieldCheck className="h-4 w-4" />
        <AlertTitle>Governed execution</AlertTitle>
        <AlertDescription>
          Aita routes to the fewest relevant Genie Agents. Genie queries run on behalf of you; the orchestrator model
          and thread store run as the app service principal.
        </AlertDescription>
      </Alert>

      <Card>
        <CardHeader>
          <CardTitle>Conversation</CardTitle>
          <CardDescription>Streamed answers retain follow-up context and expose SQL by Agent.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="h-[560px] space-y-4 overflow-y-auto rounded-md border p-4">
            {messages.length === 0 && !isStreaming && (
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

          {error && (
            <Alert variant="destructive">
              <AlertTitle>Chat failed</AlertTitle>
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}
          {metadataWarning && (
            <Alert>
              <Database className="h-4 w-4" />
              <AlertTitle>Partial persistence</AlertTitle>
              <AlertDescription>{metadataWarning}</AlertDescription>
            </Alert>
          )}

          <form
            onSubmit={(event) => {
              void ask(event);
            }}
            className="space-y-3"
          >
            <Textarea
              value={question}
              onChange={(event) => setQuestion(event.target.value)}
              placeholder="Ask about workforce, talent, recruiting, or a cross-domain question"
              disabled={isStreaming}
              rows={3}
            />
            <div className="flex flex-wrap items-center gap-2">
              <Button type="submit" disabled={isStreaming || !question.trim()}>
                <Send className="h-4 w-4" /> Ask
              </Button>
              {STARTERS.map((starter) => (
                <Button
                  key={starter.id}
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => setQuestion(starter.question)}
                  disabled={isStreaming}
                >
                  {AGENT_DEFINITIONS[starter.expectedAgent].title}
                </Button>
              ))}
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
