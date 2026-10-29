import { type FormEvent, useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router';
import { Alert, AlertDescription, AlertTitle, Button } from '@databricks/appkit-ui/react';
import { Plus, ShieldCheck } from 'lucide-react';
import type { HistoryDetail } from '../../shared/app-state';
import { AGENT_KEYS, ROUTING_CASES, type RoutingCase } from '../../shared/routing';
import type { ChatMessage } from './ChatAnswer';
import { ChatConversation } from './ChatConversation';
import {
  captureAgentEvent,
  createEvidenceCollector,
  evidenceSnapshot,
  toTurnMetadata,
  visibleAssistantContent,
} from './chat-evidence';
import { toChatMessage } from './history-chat';
import { useAitaChat } from './use-aita-chat';

const STARTERS = AGENT_KEYS.map((agent) =>
  ROUTING_CASES.find((routingCase) => routingCase.expectedAgent === agent)
).filter((routingCase): routingCase is RoutingCase => Boolean(routingCase));

export function ChatPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [question, setQuestion] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [liveEvidence, setLiveEvidence] = useState<ChatMessage['evidence']>([]);
  const [metadataWarning, setMetadataWarning] = useState<string | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const collectorRef = useRef(createEvidenceCollector());
  const rawContentRef = useRef('');

  const { content, isStreaming, error, send, reset, resume } = useAitaChat({
    agent: 'aita',
    onEvent(event) {
      if (event.type === 'response.output_text.delta' && typeof event.delta === 'string') {
        rawContentRef.current += event.delta;
      }
      if (captureAgentEvent(event, collectorRef.current)) {
        setLiveEvidence(evidenceSnapshot(collectorRef.current));
      }
    },
  });

  const requestedThreadId = searchParams.get('thread');
  const requestedPrompt = searchParams.get('prompt');

  useEffect(() => {
    if (requestedPrompt) setQuestion(requestedPrompt);
  }, [requestedPrompt]);

  useEffect(() => {
    if (!requestedThreadId) return;
    const controller = new AbortController();
    setHistoryLoading(true);
    setHistoryError(null);
    fetch(`/api/history/${encodeURIComponent(requestedThreadId)}`, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error(response.status === 404 ? 'Conversation not found.' : 'History failed.');
        return response.json() as Promise<HistoryDetail>;
      })
      .then((conversation) => {
        setMessages(conversation.messages.flatMap((message) => toChatMessage(message) ?? []));
        resume(conversation.id);
      })
      .catch((loadError: unknown) => {
        if (loadError instanceof DOMException && loadError.name === 'AbortError') return;
        setHistoryError(loadError instanceof Error ? loadError.message : 'Conversation could not be loaded.');
      })
      .finally(() => {
        if (!controller.signal.aborted) setHistoryLoading(false);
      });
    return () => controller.abort();
  }, [requestedThreadId, resume]);

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
    const activeThreadId = await send(prompt);
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
    rawContentRef.current = '';
    collectorRef.current = createEvidenceCollector();
    setMessages([]);
    setLiveEvidence([]);
    setMetadataWarning(null);
    setHistoryError(null);
    setSearchParams({}, { replace: true });
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

      <ChatConversation
        chatError={error}
        historyError={historyError}
        historyLoading={historyLoading}
        isStreaming={isStreaming}
        liveContent={liveContent}
        liveEvidence={liveEvidence}
        messages={messages}
        metadataWarning={metadataWarning}
        question={question}
        starters={STARTERS}
        onQuestionChange={setQuestion}
        onSubmit={(event) => void ask(event)}
      />
    </div>
  );
}
