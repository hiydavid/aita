import type { HistoryMessage } from '../../shared/app-state';
import type { ChatMessage } from './ChatAnswer';
import type { AgentEvidence } from './chat-evidence';
import { visibleAssistantContent } from './chat-evidence';

export function toChatMessage(message: HistoryMessage): ChatMessage | null {
  if (message.role !== 'user' && message.role !== 'assistant') return null;
  if (message.role === 'user') {
    return { id: message.id, role: 'user', content: message.content };
  }
  const evidence: AgentEvidence[] = (message.metadata?.routedAgents ?? []).map((agent) => ({
    agent,
    status: 'complete',
    conversationId: message.metadata?.genieConversationIds[agent],
    sql: message.metadata?.generatedSql[agent] ?? [],
  }));
  return {
    id: message.id,
    role: 'assistant',
    content: visibleAssistantContent(message.content),
    evidence,
    latencyMs: message.metadata?.latencyMs,
  };
}
