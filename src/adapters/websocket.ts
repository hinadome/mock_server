import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import type { MockEngine } from '../core/engine.js';
import type { EventBus } from '../core/event-bus.js';

interface WsMessage {
  action?: string;
  topic?: string;
  payload?: unknown;
}

export function registerWebSocketRoutes(
  app: FastifyInstance,
  engine: MockEngine,
  bus: EventBus,
) {
  app.get('/ws', { websocket: true }, (socket, req) => {
    handleConnection(socket, req.ip, 'demo', '/ws/demo', engine, bus);
  });

  app.get('/ws/:topic', { websocket: true }, (socket, req) => {
    const { topic } = req.params as { topic: string };
    handleConnection(socket, req.ip, topic, `/ws/${topic}`, engine, bus);
  });

  // Legacy path
  app.get('/demo', { websocket: true }, (socket, req) => {
    handleConnection(socket, req.ip, 'demo', '/ws/demo', engine, bus);
  });
}

function handleConnection(
  socket: WebSocket,
  clientIp: string | undefined,
  topic: string,
  path: string,
  engine: MockEngine,
  bus: EventBus,
) {
  const subscriptions = new Set<string>([topic]);

  socket.send(
    JSON.stringify({
      type: 'welcome',
      message: 'WebSocket demo — bidirectional persistent connection',
      protocol: 'websocket',
      path,
      topic,
      yourIp: clientIp,
      hint: 'Send {"action":"ping"} or {"action":"subscribe","topic":"orders.created"}',
    }),
  );

  const onPublish = ({ topic: t, payload }: { topic: string; payload: unknown }) => {
    if (subscriptions.has(t)) {
      socket.send(JSON.stringify({ type: 'event', topic: t, payload }));
    }
  };

  bus.on('publish', onPublish);

  socket.on('message', async (raw) => {
    let msg: WsMessage;
    try {
      msg = JSON.parse(raw.toString()) as WsMessage;
    } catch {
      socket.send(JSON.stringify({ type: 'error', message: 'Invalid JSON' }));
      return;
    }

    if (msg.action === 'subscribe' && msg.topic) {
      subscriptions.add(msg.topic);
      socket.send(JSON.stringify({ type: 'subscribed', topic: msg.topic }));
      return;
    }

    if (msg.action === 'ping') {
      socket.send(JSON.stringify({ type: 'pong', timestamp: new Date().toISOString() }));
      return;
    }

    const response = await engine.handle({
      protocol: 'websocket',
      method: 'MESSAGE',
      path,
      topic: msg.topic ?? topic,
      body: msg.payload ?? msg,
      clientIp,
    });

    socket.send(
      JSON.stringify({
        type: 'response',
        body: response.body ?? { echo: msg.payload ?? msg },
      }),
    );
  });

  socket.on('close', () => {
    bus.off('publish', onPublish);
  });
}

export async function startStandaloneWsServer(
  config: { host: string; wsPort: number },
  engine: MockEngine,
  bus: EventBus,
  logger: { info: (obj: unknown, msg?: string) => void },
) {
  const { default: Fastify } = await import('fastify');
  const { default: websocket } = await import('@fastify/websocket');

  const app = Fastify({ logger: false });
  await app.register(websocket);
  registerWebSocketRoutes(app, engine, bus);

  await app.listen({ host: config.host, port: config.wsPort });
  logger.info({ port: config.wsPort, host: config.host }, 'WebSocket server listening');
  return app;
}
