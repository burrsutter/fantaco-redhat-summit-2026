/**
 * langfuse-tracer — OpenClaw plugin
 *
 * Sends an agent trace + LLM generation to Langfuse after every agent turn.
 * Uses the Langfuse REST API directly (no npm packages required).
 *
 * Required env vars in the openclaw-gateway container:
 *   LANGFUSE_PUBLIC_KEY   — project public key  (same as LANGFUSE_INIT_PROJECT_PUBLIC_KEY)
 *   LANGFUSE_SECRET_KEY   — project secret key  (same as LANGFUSE_INIT_PROJECT_SECRET_KEY)
 *   LANGFUSE_BASE_URL     — e.g. http://172.21.0.1:3050 (Docker host gateway to Langfuse)
 */

export function register(api) {
  const publicKey = process.env.LANGFUSE_PUBLIC_KEY?.trim();
  const secretKey = process.env.LANGFUSE_SECRET_KEY?.trim();
  const baseUrl = (process.env.LANGFUSE_BASE_URL?.trim() ?? 'http://172.21.0.1:3050').replace(/\/$/, '');

  if (!publicKey || !secretKey) {
    api.logger.info('[langfuse-tracer] LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY not set — tracing disabled');
    return;
  }

  const authHeader = 'Basic ' + Buffer.from(`${publicKey}:${secretKey}`).toString('base64');
  api.logger.info(`[langfuse-tracer] Langfuse tracing enabled → ${baseUrl}`);

  // Capture the prompt text before the turn starts so we have a clean "input"
  const pendingPrompts = new Map();

  api.on('before_agent_start', (event, ctx) => {
    const key = ctx.sessionKey ?? ctx.agentId ?? 'default';
    pendingPrompts.set(key, {
      prompt: event.prompt ?? '',
      startedAt: Date.now(),
    });
  });

  api.on('agent_end', async (event, ctx) => {
    const { agentId, sessionKey } = ctx;
    const { messages, success, durationMs, error } = event;

    const key = sessionKey ?? agentId ?? 'default';
    const pending = pendingPrompts.get(key);
    pendingPrompts.delete(key);

    const now = new Date().toISOString();
    const startedAt = pending?.startedAt ?? (durationMs ? Date.now() - durationMs : Date.now());
    const startTime = new Date(startedAt).toISOString();

    // --- Extract input: prefer captured prompt, fall back to last user message ---
    let input = pending?.prompt ?? '';
    if (!input) {
      for (let i = messages.length - 1; i >= 0; i--) {
        const msg = messages[i];
        if (msg?.role === 'user') {
          input = extractText(msg.content, 2000);
          break;
        }
      }
    }

    // --- Extract output: last assistant message text ---
    let output = '';
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i];
      if (msg?.role === 'assistant') {
        output = extractText(msg.content, 4000);
        break;
      }
    }

    // --- Extract token usage from last assistant message with usage field ---
    let usage;
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i];
      if (msg?.role === 'assistant' && msg.usage) {
        const u = msg.usage;
        usage = {
          input: typeof u.input_tokens === 'number' ? u.input_tokens : undefined,
          output: typeof u.output_tokens === 'number' ? u.output_tokens : undefined,
          unit: 'TOKENS',
        };
        break;
      }
    }

    const traceId = randomId();
    const generationId = randomId();
    const batchItemId1 = randomId();
    const batchItemId2 = randomId();

    const batch = [
      {
        id: batchItemId1,
        type: 'trace-create',
        timestamp: now,
        body: {
          id: traceId,
          name: 'openclaw-turn',
          sessionId: sessionKey ?? undefined,
          userId: agentId ?? 'unknown',
          tags: ['openclaw', agentId ?? 'unknown'],
          input: input.slice(0, 2000) || undefined,
          output: output.slice(0, 4000) || undefined,
          metadata: {
            success,
            error: error ?? undefined,
            messageCount: messages.length,
          },
          timestamp: startTime,
        },
      },
      {
        id: batchItemId2,
        type: 'generation-create',
        timestamp: now,
        body: {
          id: generationId,
          traceId,
          name: 'llm',
          startTime,
          endTime: now,
          input: input.slice(0, 2000) || undefined,
          output: output.slice(0, 4000) || undefined,
          level: success ? 'DEFAULT' : 'ERROR',
          statusMessage: error ?? undefined,
          usage,
          metadata: {
            durationMs,
            messageCount: messages.length,
          },
        },
      },
    ];

    try {
      const res = await fetch(`${baseUrl}/api/public/ingestion`, {
        method: 'POST',
        headers: {
          Authorization: authHeader,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ batch }),
      });
      if (!res.ok) {
        const text = await res.text().catch(() => '');
        api.logger.warn(`[langfuse-tracer] Ingestion failed ${res.status}: ${text.slice(0, 200)}`);
      }
    } catch (err) {
      api.logger.warn(`[langfuse-tracer] Fetch error: ${String(err)}`);
    }
  });
}

// ── helpers ──────────────────────────────────────────────────────────────────

function extractText(content, maxLen) {
  if (typeof content === 'string') {
    return content.slice(0, maxLen);
  }
  if (Array.isArray(content)) {
    return content
      .filter((c) => c?.type === 'text' && typeof c.text === 'string')
      .map((c) => c.text)
      .join('\n')
      .slice(0, maxLen);
  }
  return '';
}

function randomId() {
  return crypto.randomUUID();
}
