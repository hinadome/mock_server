import type { FastifyInstance } from 'fastify';
import type { MockEngine } from '../core/engine.js';
import type { EventBus } from '../core/event-bus.js';
import { delay } from '../core/event-bus.js';

function encodeChunk(chunk: unknown, format: string): string {
  if (format === 'text') {
    if (typeof chunk === 'string') return `${chunk}\n`;
    if (chunk && typeof chunk === 'object' && 'message' in chunk) {
      return `${String((chunk as { message: unknown }).message)}\n`;
    }
    if (chunk && typeof chunk === 'object' && 'token' in chunk) {
      return String((chunk as { token: unknown }).token);
    }
    return `${JSON.stringify(chunk)}\n`;
  }
  // ndjson (default) — one JSON value per line for fetch ReadableStream consumers
  return `${JSON.stringify(chunk)}\n`;
}

export function registerHttpStreamRoutes(
  app: FastifyInstance,
  engine: MockEngine,
  bus: EventBus,
) {
  app.get('/http-stream', async (_req, reply) => {
    return reply.redirect('/http-stream/demo');
  });

  app.get('/http-stream/:name', async (req, reply) => {
    const { name } = req.params as { name: string };
    const query = req.query as Record<string, string>;
    const format = (query.format ?? 'ndjson').toLowerCase();

    const response = await engine.handle({
      protocol: 'httpStream',
      method: 'GET',
      path: `/http-stream/${name}`,
      topic: name,
      query,
      headers: req.headers as Record<string, string>,
      clientIp: req.ip,
    });

    if (response.error) {
      return reply.code(response.status ?? 500).send(response.error);
    }

    const contentType =
      response.headers?.['Content-Type'] ??
      response.headers?.['content-type'] ??
      (format === 'text' ? 'text/plain; charset=utf-8' : 'application/x-ndjson');

    const headers: Record<string, string> = {
      'Content-Type': contentType,
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
      ...(response.headers ?? {}),
    };
    // Ensure Content-Type wins if headers had a different casing duplicate
    headers['Content-Type'] = contentType;

    reply.hijack();
    reply.raw.writeHead(response.status ?? 200, headers);

    const writeChunk = (chunk: unknown) => {
      if (!reply.raw.writableEnded) {
        reply.raw.write(encodeChunk(chunk, format));
      }
    };

    const chunks =
      response.stream && response.stream.length > 0
        ? response.stream
        : [
            {
              type: 'connected',
              protocol: 'httpStream',
              path: `/http-stream/${name}`,
              message: 'HTTP Streams (Fetch) — no stream chunks configured',
              yourIp: req.ip,
            },
          ];

    const chunkDelay = response.chunkDelayMs ?? 0;
    let closed = false;

    const onClose = () => {
      closed = true;
      bus.off('publish', onPublish);
    };
    req.raw.on('close', onClose);

    const onPublish = ({ topic: t, payload }: { topic: string; payload: unknown }) => {
      if (closed) return;
      if (t === name || name === '+') {
        writeChunk({ type: 'message', topic: t, data: payload });
      }
    };

    for (const chunk of chunks) {
      if (closed) break;
      writeChunk(chunk);
      if (chunkDelay > 0) await delay(chunkDelay);
    }

    const keepOpen = response.keepOpen === true;
    if (keepOpen && !closed) {
      bus.on('publish', onPublish);
      // Connection stays open until client disconnects
      return;
    }

    bus.off('publish', onPublish);
    req.raw.off('close', onClose);
    if (!reply.raw.writableEnded) {
      reply.raw.end();
    }
  });
}
