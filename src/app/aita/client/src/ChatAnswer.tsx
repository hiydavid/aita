import { Badge, Card, CardContent, CardHeader, CardTitle, cn } from '@databricks/appkit-ui/react';
import DOMPurify from 'dompurify';
import { marked } from 'marked';
import { useMemo } from 'react';
import { AGENT_DEFINITIONS } from '../../shared/routing';
import type { AgentEvidence } from './chat-evidence';

// Same renderer as AppKit's Genie chat: GFM markdown, sanitized before it reaches the DOM.
marked.setOptions({ breaks: true, gfm: true });

const markdownStyles = cn(
  'text-sm leading-6 break-words',
  '[&_p]:my-2 [&_strong]:font-semibold [&_h1]:font-semibold [&_h2]:font-semibold [&_h3]:font-semibold',
  '[&_ul]:my-2 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:my-2 [&_ol]:list-decimal [&_ol]:pl-5 [&_li]:my-0.5',
  '[&_code]:rounded [&_code]:bg-muted [&_code]:px-1 [&_code]:text-xs',
  '[&_table]:my-3 [&_table]:block [&_table]:max-w-full [&_table]:overflow-x-auto [&_table]:border-collapse [&_table]:text-xs',
  '[&_th]:border [&_th]:border-border [&_th]:px-2 [&_th]:py-1 [&_th]:text-left [&_th]:font-medium',
  '[&_td]:border [&_td]:border-border [&_td]:px-2 [&_td]:py-1',
  '[&_a]:underline'
);

export function AnswerMarkdown({ content }: { content: string }) {
  const html = useMemo(() => DOMPurify.sanitize(marked.parse(content, { async: false })), [content]);
  return <div className={markdownStyles} dangerouslySetInnerHTML={{ __html: html }} />;
}

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
        <AnswerMarkdown content={item.content} />
        <ChatEvidence evidence={item.evidence ?? []} />
        <p className="text-xs text-muted-foreground">
          AI-generated from governed data via Genie — verify against the SQL and source. Watchlist signals require human
          review.
        </p>
      </CardContent>
    </Card>
  );
}
