import { createSchema, createYoga } from 'graphql-yoga';
import { useServer } from 'graphql-ws/use/ws';
import type { FastifyInstance } from 'fastify';
import type { WebSocketServer } from 'ws';
import type { MockEngine } from '../core/engine.js';
import type { EventBus } from '../core/event-bus.js';

const DEMO_EXPLAINER =
  'GraphQL — clients send queries to one endpoint; the server returns exactly the fields requested.';

async function resolveField(
  engine: MockEngine,
  operation: string,
  args: Record<string, unknown>,
  fallback: unknown,
) {
  const response = await engine.handle({
    protocol: 'graphql',
    method: 'QUERY',
    path: operation,
    body: args,
  });
  if (response.status === 404) return fallback;
  return response.body ?? fallback;
}

async function* countdown(from: number): AsyncGenerator<number> {
  for (let i = from; i >= 0; i--) {
    yield i;
    if (i > 0) await new Promise((r) => setTimeout(r, 1000));
  }
}

function orderCreatedIterator(bus: EventBus): AsyncGenerator<{ orderId: string; status: string; item?: string }> {
  return (async function* () {
    const queue: Array<{ orderId: string; status: string; item?: string }> = [];
    let wake: (() => void) | undefined;
    let done = false;

    const onPublish = ({ topic, payload }: { topic: string; payload: unknown }) => {
      if (topic !== 'orders.created') return;
      const p = (payload ?? {}) as { orderId?: string; status?: string; item?: string };
      queue.push({
        orderId: p.orderId ?? 'order-123',
        status: p.status ?? 'created',
        item: p.item,
      });
      wake?.();
    };

    bus.on('publish', onPublish);

    try {
      while (!done) {
        if (queue.length === 0) {
          await new Promise<void>((resolve) => {
            wake = resolve;
          });
        }
        while (queue.length) {
          yield queue.shift()!;
        }
      }
    } finally {
      bus.off('publish', onPublish);
      done = true;
    }
  })();
}

export function registerGraphqlRoutes(
  app: FastifyInstance,
  engine: MockEngine,
  schemaSdl: string,
  bus: EventBus,
) {
  const schema = createSchema({
    typeDefs: schemaSdl,
    resolvers: {
      Query: {
        demo: () => DEMO_EXPLAINER,
        hello: (_: unknown, args: { name?: string }) =>
          resolveField(engine, 'hello', args, `Hello, ${args.name ?? 'world'}!`),
        user: (_: unknown, args: { id: string }) =>
          resolveField(engine, 'user', args, {
            id: args.id,
            name: 'Ada Lovelace',
            email: 'ada@example.com',
          }),
        users: () =>
          resolveField(engine, 'users', {}, [
            { id: '1', name: 'Ada Lovelace', email: 'ada@example.com' },
            { id: '2', name: 'Grace Hopper', email: 'grace@example.com' },
          ]),
      },
      Mutation: {
        createUser: (_: unknown, args: { name: string; email?: string }) =>
          resolveField(engine, 'createUser', args, {
            id: 'user-new',
            name: args.name,
            email: args.email ?? null,
          }),
        updateUser: (_: unknown, args: { id: string; name?: string }) =>
          resolveField(engine, 'updateUser', args, {
            id: args.id,
            name: args.name ?? 'Ada Lovelace',
            email: 'ada@example.com',
          }),
        deleteUser: (_: unknown, args: { id: string }) =>
          resolveField(engine, 'deleteUser', args, { id: args.id, deleted: true }),
        publishOrder: async (_: unknown, args: { item?: string }) => {
          const event = {
            orderId: `order-${Date.now()}`,
            status: 'created',
            item: args.item ?? 'unknown',
          };
          bus.emit('publish', { topic: 'orders.created', payload: event });
          await engine.handle({
            protocol: 'graphql',
            method: 'MUTATION',
            path: 'publishOrder',
            body: args,
          });
          return event;
        },
      },
      Subscription: {
        countdown: {
          subscribe: (_: unknown, args: { from?: number }) => countdown(args.from ?? 3),
          resolve: (value: number) => value,
        },
        orderCreated: {
          subscribe: () => orderCreatedIterator(bus),
          resolve: (value: unknown) => value,
        },
      },
    },
  });

  const yoga = createYoga({
    schema,
    graphqlEndpoint: '/graphql',
    landingPage: true,
    graphiql: {
      subscriptionsProtocol: 'WS',
    },
  });

  app.get('/graphql/demo', async (req, reply) => {
    await engine.handle({
      protocol: 'graphql',
      method: 'QUERY',
      path: '/graphql/demo',
      clientIp: req.ip,
    });
    return reply.send({
      data: {
        demo: DEMO_EXPLAINER,
        path: '/graphql/demo',
        yourIp: req.ip,
        samples: {
          query: '{ users { id name } }',
          mutation: 'mutation { createUser(name: "Ada") { id name } }',
          subscription: 'subscription { countdown(from: 3) }',
          subscriptionOrders: 'subscription { orderCreated { orderId status item } }',
        },
        hint: 'Open /graphql for GraphiQL. Subscriptions use graphql-ws on the same /graphql WebSocket.',
      },
    });
  });

  app.get('/graphql/hello', async (req, reply) => {
    const query = req.query as { name?: string };
    const name = query.name ?? 'world';
    const message = await resolveField(engine, 'hello', { name }, `Hello, ${name}!`);
    return reply.send({
      data: { hello: message, path: '/graphql/hello' },
    });
  });

  app.all('/graphql', async (req, reply) => {
    // WebSocket upgrades are handled by graphql-ws — skip HTTP handler
    if (req.headers.upgrade?.toLowerCase() === 'websocket') {
      return reply;
    }

    const url = `http://${req.headers.host ?? 'localhost'}/graphql`;
    const body =
      req.method === 'GET'
        ? undefined
        : typeof req.body === 'string'
          ? req.body
          : JSON.stringify(req.body ?? {});

    const request = new Request(url, {
      method: req.method,
      headers: req.headers as HeadersInit,
      body: req.method === 'GET' ? undefined : body,
    });

    const response = await yoga.fetch(request);
    reply.code(response.status);
    response.headers.forEach((value, key) => {
      reply.header(key, value);
    });
    return reply.send(Buffer.from(await response.arrayBuffer()));
  });

  return { schema, yoga };
}

/** Attach graphql-ws to an existing ws.Server (HTTP upgrade on /graphql). */
export function attachGraphqlWs(
  wss: WebSocketServer,
  schema: ReturnType<typeof createSchema>,
) {
  useServer({ schema }, wss);
}
