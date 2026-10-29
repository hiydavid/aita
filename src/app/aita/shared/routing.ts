export const AGENT_KEYS = ['workforce_attrition', 'talent_performance', 'recruiting'] as const;

export type AgentKey = (typeof AGENT_KEYS)[number];

export const AGENT_DEFINITIONS: Record<AgentKey, { title: string; description: string }> = {
  workforce_attrition: {
    title: 'Workforce & Attrition',
    description:
      'Executive workforce, headcount, attrition, engagement, productivity, and governed talent-watchlist analysis for HR and business leaders.',
  },
  talent_performance: {
    title: 'Talent & Performance',
    description:
      'Executive talent, performance, promotion, governed pay-position, skills, and GenAI-exposure analysis for HR and business leaders.',
  },
  recruiting: {
    title: 'Recruiting',
    description:
      'Executive requisition, hiring-funnel, time-to-fill, offer, backfill, and internal-mobility analysis for HR and business leaders.',
  },
};

export interface RoutingCase {
  id: string;
  question: string;
  expectedAgent: AgentKey;
}

export const ROUTING_CASES: RoutingCase[] = [
  {
    id: '41000000000000000000000000000001',
    question: 'How has voluntary attrition tracked YTD versus the last two years, by business line?',
    expectedAgent: 'workforce_attrition',
  },
  {
    id: '41000000000000000000000000000005',
    question: 'Where is the burnout-or-workload signal rate highest?',
    expectedAgent: 'workforce_attrition',
  },
  {
    id: '41000000000000000000000000000007',
    question: 'Who is on the watchlist in Consumer Banking, and why?',
    expectedAgent: 'workforce_attrition',
  },
  {
    id: '42000000000000000000000000000001',
    question: 'Which senior high performers have not been promoted in three or more years?',
    expectedAgent: 'talent_performance',
  },
  {
    id: '42000000000000000000000000000004',
    question: 'What AI-extracted skills show up most often for high performers in Technology?',
    expectedAgent: 'talent_performance',
  },
  {
    id: '42000000000000000000000000000006',
    question: 'Which job families have the highest below-midpoint share?',
    expectedAgent: 'talent_performance',
  },
  {
    id: '43000000000000000000000000000001',
    question: 'What is the average time to fill for licensed advisor roles versus all other roles?',
    expectedAgent: 'recruiting',
  },
  {
    id: '43000000000000000000000000000004',
    question: 'Which open roles have internal applicants from GenAI-exposed job families?',
    expectedAgent: 'recruiting',
  },
  {
    id: '43000000000000000000000000000007',
    question: 'Which business lines have the most open requisitions?',
    expectedAgent: 'recruiting',
  },
];

export interface SqlEvidence {
  title?: string;
  query: string;
}

export interface TurnMetadataInput {
  routedAgents: AgentKey[];
  genieConversationIds: Partial<Record<AgentKey, string>>;
  generatedSql: Partial<Record<AgentKey, SqlEvidence[]>>;
  latencyMs: number;
}
