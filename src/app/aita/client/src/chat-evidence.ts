import type { AgentChatEvent } from '@databricks/appkit-ui/react';
import { AGENT_KEYS, type AgentKey, type SqlEvidence, type TurnMetadataInput } from '../../shared/routing';

export interface AgentEvidence {
  agent: AgentKey;
  status: 'running' | 'complete' | 'error';
  conversationId?: string;
  sql: SqlEvidence[];
  error?: string;
}

export interface EvidenceCollector {
  calls: Map<string, AgentKey>;
  agents: Map<AgentKey, AgentEvidence>;
}

export function createEvidenceCollector(): EvidenceCollector {
  return { calls: new Map(), agents: new Map() };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isAgentKey(value: unknown): value is AgentKey {
  return typeof value === 'string' && AGENT_KEYS.some((agent) => agent === value);
}

function addSql(evidence: AgentEvidence, value: unknown): void {
  if (!isRecord(value) || !Array.isArray(value.attachments)) return;
  for (const attachment of value.attachments) {
    if (!isRecord(attachment) || !isRecord(attachment.query)) continue;
    const query = attachment.query.query;
    const title = attachment.query.title;
    if (typeof query !== 'string') continue;
    if (evidence.sql.some((statement) => statement.query === query)) continue;
    evidence.sql.push({
      query,
      ...(typeof title === 'string' ? { title } : {}),
    });
  }
}

function applyGenieOutput(evidence: AgentEvidence, output: string): void {
  let parsed: unknown;
  try {
    parsed = JSON.parse(output);
  } catch {
    evidence.status = 'error';
    evidence.error = 'Genie returned unreadable evidence.';
    return;
  }
  if (!Array.isArray(parsed)) return;
  for (const genieEvent of parsed) {
    if (!isRecord(genieEvent)) continue;
    if (genieEvent.type === 'message_start' && typeof genieEvent.conversationId === 'string') {
      evidence.conversationId = genieEvent.conversationId;
    }
    if (genieEvent.type === 'message_result' && isRecord(genieEvent.message)) {
      if (typeof genieEvent.message.conversationId === 'string') {
        evidence.conversationId = genieEvent.message.conversationId;
      }
      addSql(evidence, genieEvent.message);
    }
    if (genieEvent.type === 'error' && typeof genieEvent.error === 'string') {
      evidence.status = 'error';
      evidence.error = genieEvent.error;
    }
  }
}

export function captureAgentEvent(event: AgentChatEvent, collector: EvidenceCollector): boolean {
  const item = event.item;
  if (
    event.type === 'response.output_item.added' &&
    item?.type === 'function_call' &&
    typeof item.call_id === 'string' &&
    isAgentKey(item.name)
  ) {
    collector.calls.set(item.call_id, item.name);
    collector.agents.set(item.name, {
      agent: item.name,
      status: 'running',
      sql: [],
    });
    return true;
  }
  if (
    event.type !== 'response.output_item.done' ||
    item?.type !== 'function_call_output' ||
    typeof item.call_id !== 'string' ||
    typeof item.output !== 'string'
  ) {
    return false;
  }
  const agent = collector.calls.get(item.call_id);
  if (!agent) return false;
  const evidence = collector.agents.get(agent) ?? {
    agent,
    status: 'running',
    sql: [],
  };
  applyGenieOutput(evidence, item.output);
  if (evidence.status !== 'error') evidence.status = 'complete';
  collector.agents.set(agent, evidence);
  return true;
}

export function evidenceSnapshot(collector: EvidenceCollector): AgentEvidence[] {
  return AGENT_KEYS.flatMap((agent) => {
    const evidence = collector.agents.get(agent);
    return evidence ? [evidence] : [];
  });
}

export function visibleAssistantContent(content: string): string {
  const markerIndex = content.indexOf('<AITA_CONTEXT>');
  return (markerIndex >= 0 ? content.slice(0, markerIndex) : content).trim();
}

export function toTurnMetadata(evidence: AgentEvidence[], latencyMs: number): TurnMetadataInput {
  const genieConversationIds: TurnMetadataInput['genieConversationIds'] = {};
  const generatedSql: TurnMetadataInput['generatedSql'] = {};
  for (const item of evidence) {
    if (item.conversationId) {
      genieConversationIds[item.agent] = item.conversationId;
    }
    generatedSql[item.agent] = item.sql;
  }
  return {
    routedAgents: evidence.map((item) => item.agent),
    genieConversationIds,
    generatedSql,
    latencyMs,
  };
}
