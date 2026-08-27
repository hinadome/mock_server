import type { FastifyInstance } from 'fastify';
import type { MockEngine } from '../core/engine.js';

/** HTTP path helpers so gRPC demos can be tried with curl: GET /grpc/demo */
export function registerGrpcHttpRoutes(app: FastifyInstance, engine: MockEngine) {
  app.get('/grpc', async (_req, reply) => reply.redirect('/grpc/demo'));

  app.get('/grpc/demo', async (req, reply) => {
    const response = await engine.handle({
      protocol: 'grpc',
      method: 'Ping',
      path: 'DemoService/Ping',
      body: { message: 'hello' },
      clientIp: req.ip,
    });

    return reply.send({
      message: (response.body as { message?: string })?.message ?? 'Pong: hello',
      protocol: 'grpc',
      path: '/grpc/demo',
      yourIp: req.ip,
      hint: 'Real gRPC: grpcurl -plaintext HOST:50051 demo.DemoService/Ping',
    });
  });

  app.get('/grpc/ping', async (req, reply) => {
    const query = req.query as { message?: string };
    const message = query.message ?? 'hello';
    const response = await engine.handle({
      protocol: 'grpc',
      method: 'Ping',
      path: 'DemoService/Ping',
      body: { message },
      clientIp: req.ip,
    });

    return reply.send({
      message: (response.body as { message?: string })?.message ?? `Pong: ${message}`,
      protocol: 'grpc',
      path: '/grpc/ping',
    });
  });
}
