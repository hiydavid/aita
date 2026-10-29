import { useCallback, useEffect, useRef, useState } from 'react';
import type { AgentChatEvent } from '@databricks/appkit-ui/react';

interface AitaChatOptions {
  agent: string;
  onEvent?: (event: AgentChatEvent) => void;
}

export function useAitaChat({ agent, onEvent }: AitaChatOptions) {
  const [content, setContent] = useState('');
  const [threadId, setThreadId] = useState<string | null>(null);
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const threadIdRef = useRef<string | null>(null);
  const onEventRef = useRef(onEvent);
  const abortRef = useRef<AbortController | null>(null);
  onEventRef.current = onEvent;

  const clearStream = useCallback(() => {
    abortRef.current?.abort();
    abortRef.current = null;
    setContent('');
    setIsStreaming(false);
    setError(null);
  }, []);

  const reset = useCallback(() => {
    clearStream();
    threadIdRef.current = null;
    setThreadId(null);
  }, [clearStream]);

  const resume = useCallback(
    (id: string) => {
      clearStream();
      threadIdRef.current = id;
      setThreadId(id);
    },
    [clearStream]
  );

  const send = useCallback(
    async (message: string) => {
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;
      setContent('');
      setError(null);
      setIsStreaming(true);
      let streamedContent = '';
      let activeThreadId = threadIdRef.current;
      try {
        const response = await fetch('/api/agents/chat', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            message,
            agent,
            ...(threadIdRef.current ? { threadId: threadIdRef.current } : {}),
          }),
          signal: controller.signal,
        });
        if (!response.ok || !response.body) {
          throw new Error(response.status === 401 ? 'Your session is not authorized for chat.' : 'Chat stream failed.');
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          buffer = buffer.replace(/\r\n/g, '\n');
          if (buffer.length > 2_000_000) throw new Error('Chat response exceeded the safe display limit.');
          let boundary = buffer.indexOf('\n\n');
          while (boundary >= 0) {
            const frame = buffer.slice(0, boundary);
            buffer = buffer.slice(boundary + 2);
            const data = frame
              .split('\n')
              .filter((line) => line.startsWith('data:'))
              .map((line) => line.slice(5).trimStart())
              .join('\n');
            if (data && data !== '[DONE]') {
              const parsed: unknown = JSON.parse(data);
              if (isAgentEvent(parsed)) {
                try {
                  onEventRef.current?.(parsed);
                } catch {
                  setError('The answer streamed, but some supporting evidence could not be displayed.');
                }
                if (parsed.type === 'appkit.metadata' && typeof parsed.data?.threadId === 'string') {
                  threadIdRef.current = parsed.data.threadId;
                  activeThreadId = parsed.data.threadId;
                  setThreadId(parsed.data.threadId);
                }
                if (parsed.type === 'response.output_text.delta' && typeof parsed.delta === 'string') {
                  streamedContent += parsed.delta;
                  setContent(streamedContent);
                }
              }
            }
            boundary = buffer.indexOf('\n\n');
          }
        }
      } catch (streamError) {
        if (!controller.signal.aborted) {
          setError(streamError instanceof Error ? streamError.message : 'Chat stream failed.');
        }
      } finally {
        if (abortRef.current === controller) abortRef.current = null;
        setIsStreaming(false);
      }
      return activeThreadId;
    },
    [agent]
  );

  useEffect(() => () => abortRef.current?.abort(), []);

  return { content, threadId, isStreaming, error, send, reset, resume };
}

function isAgentEvent(value: unknown): value is AgentChatEvent {
  return typeof value === 'object' && value !== null && typeof (value as { type?: unknown }).type === 'string';
}
