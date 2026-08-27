import Fastify from 'fastify';
import cors from '@fastify/cors';
import type { MockEngine } from '../core/engine.js';
import type { ServerConfig } from '../core/types.js';
import type { Logger } from '../utils/logger.js';
import { loadTlsOptions } from '../auth/jwt.js';

export async function createHttpServer(config: ServerConfig) {
  const https = loadTlsOptions(config);
  const app = Fastify({
    logger: false,
    ...(https ? { https } : {}),
  });

  await app.register(cors, {
    origin: config.corsOrigins.includes('*') ? true : config.corsOrigins,
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    strictPreflight: false,
  });

  return app;
}

export function registerHttpMockRoutes(
  app: Awaited<ReturnType<typeof createHttpServer>>,
  engine: MockEngine,
) {
  app.get('/http', async (_req, reply) => reply.redirect('/http/demo'));

  app.all('/http/demo', async (req, reply) => {
    const response = await engine.handle({
      protocol: 'http',
      method: req.method,
      path: '/http/demo',
      headers: req.headers as Record<string, string>,
      query: req.query as Record<string, string>,
      body: req.body,
      clientIp: req.ip,
    });
    return reply.code(response.status ?? 200).send(
      response.body ?? {
        message: 'HTTP demo — request/response over REST',
        protocol: 'http',
        path: '/http/demo',
        yourIp: req.ip,
      },
    );
  });

  app.all('/demo/http', async (_req, reply) => reply.redirect('/http/demo'));

  app.options('/http/users', async (req, reply) => {
    const response = await engine.handle({
      protocol: 'http',
      method: 'OPTIONS',
      path: '/http/users',
      headers: req.headers as Record<string, string>,
      clientIp: req.ip,
    });
    return reply
      .code(response.status ?? 204)
      .headers(response.headers ?? { Allow: 'GET, POST, OPTIONS' })
      .send();
  });

  app.setNotFoundHandler(async (req, reply) => {
    const path = req.url.split('?')[0];
    const response = await engine.handle({
      protocol: 'http',
      method: req.method,
      path,
      headers: req.headers as Record<string, string>,
      query: req.query as Record<string, string>,
      body: req.body,
      clientIp: req.ip,
    });

    if (response.error) {
      return reply.code(response.status ?? 500).send(response.error);
    }

    const code = response.status ?? 200;
    if (req.method === 'HEAD' || code === 204) {
      return reply.code(code).headers(response.headers ?? {}).send();
    }
    return reply.code(code).headers(response.headers ?? {}).send(response.body);
  });
}

export async function startHttpServer(
  app: Awaited<ReturnType<typeof createHttpServer>>,
  config: ServerConfig,
  logger: Logger,
) {
  await app.listen({ host: config.host, port: config.httpPort });
  logger.info(
    {
      port: config.httpPort,
      host: config.host,
      tls: Boolean(config.tls.enabled && config.tls.certPath),
      mtls: config.tls.requestClientCert,
      authRequired: config.auth.requireAuth,
    },
    'HTTP server listening',
  );
}
