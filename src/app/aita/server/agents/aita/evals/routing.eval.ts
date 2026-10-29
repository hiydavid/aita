import { defineEval, equals } from '@databricks/appkit/beta';
import { ROUTING_CASES } from '../../../../shared/routing';

export default defineEval({
  description: 'Routes three canonical questions to each domain Agent',
  tags: ['routing', 'phase-13'],
  timeoutMs: 900_000,
  async test(context) {
    for (const routingCase of ROUTING_CASES) {
      await context.send(routingCase.question);
      context.succeeded();
      context.calledTool(routingCase.expectedAgent);
      const routedAgents = [...new Set(context.toolCalls)].sort();
      context.check(routedAgents.join(','), equals(routingCase.expectedAgent));
      context.reset();
    }
  },
});
