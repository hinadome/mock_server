import type { FastifyInstance } from 'fastify';
import type { MockEngine } from '../core/engine.js';
import type { EventBus } from '../core/event-bus.js';

export function registerSseRoutes(app: FastifyInstance, engine: MockEngine, bus: EventBus) {
  app.get('/sse', async (_req, reply) => {
    return reply.redirect('/sse/demo');
  });

  app.get('/sse/:topic', async (req, reply) => {
    const { topic } = req.params as { topic: string };
    const query = req.query as Record<string, string>;

    await engine.handle({
      protocol: 'sse',
      method: 'GET',
      path: `/sse/${topic}`,
      topic,
      query,
      clientIp: req.ip,
    });

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    });

    const send = (event: string, data: unknown) => {
      reply.raw.write(`event: ${event}\n`);
      reply.raw.write(`data: ${JSON.stringify(data)}\n\n`);
    };

    send('connected', {
      message: 'SSE demo — one-way server push over HTTP',
      protocol: 'sse',
      topic,
      path: `/sse/${topic}`,
      yourIp: req.ip,
    });

    if (topic === 'demo') {
      let count = 0;
      const demoInterval = setInterval(() => {
        count += 1;
        send('demo', { count, message: `Demo event ${count}/3` });
        if (count >= 3) clearInterval(demoInterval);
      }, 1000);
    }

    const onPublish = ({ topic: t, payload }: { topic: string; payload: unknown }) => {
      if (t === topic || topic === '+') {
        send('message', payload);
      }
    };

    bus.on('publish', onPublish);

    req.raw.on('close', () => {
      bus.off('publish', onPublish);
    });
  });
}
