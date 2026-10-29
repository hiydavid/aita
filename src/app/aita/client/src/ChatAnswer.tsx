import { Badge, Card, CardContent, CardHeader, CardTitle } from '@databricks/appkit-ui/react';
import { AGENT_DEFINITIONS } from '../../shared/routing';
import type { AgentEvidence } from './chat-evidence';

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  evidence?: AgentEvidence[];
  latencyMs?: number;
}

export function ChatEvidence({ evidence }: { evidence: AgentEvidence[] }) {
  if (evidence.length === 0) {
    return <Badge variant="outline">Clarification — no Agent called</Badge>;
  }
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {evidence.map((item) => (
          <Badge key={item.agent} variant={item.status === 'error' ? 'destructive' : 'secondary'}>
            {AGENT_DEFINITIONS[item.agent].title} · {item.status}
          </Badge>
        ))}
      </div>
      {evidence.map((item) => (
        <div key={item.agent} className="space-y-2">
          {item.error && <p className="text-sm text-destructive">{item.error}</p>}
          {item.status === 'complete' && item.sql.length === 0 && (
            <p className="text-xs text-muted-foreground">
              {AGENT_DEFINITIONS[item.agent].title} returned no SQL attachment.
            </p>
          )}
          {item.sql.map((statement) => (
            <details key={`${item.agent}-${statement.query}`} className="rounded-md border">
              <summary className="cursor-pointer px-3 py-2 text-sm font-medium">
                Generated SQL · {AGENT_DEFINITIONS[item.agent].title}
              </summary>
              <pre className="overflow-auto border-t bg-muted/40 p-3 text-xs">{statement.query}</pre>
            </details>
          ))}
        </div>
      ))}
    </div>
  );
}

export function AssistantAnswer({ item }: { item: ChatMessage }) {
  return (
    <Card className="max-w-4xl">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between gap-3">
          <CardTitle className="text-base">Aita</CardTitle>
          {item.latencyMs !== undefined && (
            <span className="text-xs text-muted-foreground">{(item.latencyMs / 1000).toFixed(1)}s</span>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="whitespace-pre-wrap text-sm leading-6">{item.content}</div>
        <ChatEvidence evidence={item.evidence ?? []} />
        <p className="text-xs text-muted-foreground">
          AI-generated from governed data via Genie — verify against the SQL and source. Watchlist signals require human
          review.
        </p>
      </CardContent>
    </Card>
  );
}
