import { AGENT_KEYS, type AgentKey, type SqlEvidence, type TurnMetadataInput } from '../shared/routing';

export function parseTurnMetadata(value: unknown): TurnMetadataInput | null {
  if (!isRecord(value)) return null;
  const routedAgents = value.routedAgents;
  const latencyMs = value.latencyMs;
  if (
    !Array.isArray(routedAgents) ||
    routedAgents.length > AGENT_KEYS.length ||
    !routedAgents.every(isAgentKey) ||
    new Set(routedAgents).size !== routedAgents.length ||
    typeof latencyMs !== 'number' ||
    !Number.isInteger(latencyMs) ||
    latencyMs < 0 ||
    latencyMs > 600_000 ||
    !isRecord(value.genieConversationIds) ||
    !isRecord(value.generatedSql)
  ) {
    return null;
  }

  const genieConversationIds: Partial<Record<AgentKey, string>> = {};
  const generatedSql: Partial<Record<AgentKey, SqlEvidence[]>> = {};
  for (const agent of AGENT_KEYS) {
    const conversationId = value.genieConversationIds[agent];
    if (conversationId !== undefined) {
      if (typeof conversationId !== 'string' || conversationId.length > 128) return null;
      genieConversationIds[agent] = conversationId;
    }
    const statements = parseSqlEvidence(value.generatedSql[agent]);
    if (statements === null) return null;
    if (statements) generatedSql[agent] = statements;
  }
  return { routedAgents, genieConversationIds, generatedSql, latencyMs };
}

function parseSqlEvidence(value: unknown): SqlEvidence[] | undefined | null {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length > 20) return null;
  const statements: SqlEvidence[] = [];
  for (const statement of value) {
    if (!isRecord(statement) || typeof statement.query !== 'string' || statement.query.length > 50_000) return null;
    if (statement.title !== undefined && typeof statement.title !== 'string') return null;
    statements.push({
      query: statement.query,
      ...(statement.title ? { title: statement.title.slice(0, 500) } : {}),
    });
  }
  return statements;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isAgentKey(value: unknown): value is AgentKey {
  return typeof value === 'string' && AGENT_KEYS.some((agent) => agent === value);
}
