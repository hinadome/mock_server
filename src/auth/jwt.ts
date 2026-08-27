import { readFileSync, existsSync } from 'node:fs';
import { SignJWT, jwtVerify } from 'jose';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { AuthConfig, ServerConfig } from '../core/types.js';

export function loadTlsOptions(config: ServerConfig):
  | { key: Buffer; cert: Buffer; ca?: Buffer; requestCert?: boolean; rejectUnauthorized?: boolean }
  | undefined {
  if (!config.tls.enabled || !config.tls.certPath || !config.tls.keyPath) return undefined;
  if (!existsSync(config.tls.certPath) || !existsSync(config.tls.keyPath)) {
    throw new Error(`TLS enabled but cert/key not found: ${config.tls.certPath}, ${config.tls.keyPath}`);
  }

  const opts: {
    key: Buffer;
    cert: Buffer;
    ca?: Buffer;
    requestCert?: boolean;
    rejectUnauthorized?: boolean;
  } = {
    key: readFileSync(config.tls.keyPath),
    cert: readFileSync(config.tls.certPath),
  };

  if (config.tls.caPath && existsSync(config.tls.caPath)) {
    opts.ca = readFileSync(config.tls.caPath);
  }

  if (config.tls.requestClientCert) {
    opts.requestCert = true;
    opts.rejectUnauthorized = true;
  }

  return opts;
}

function isPublicPath(path: string, publicPaths: string[]): boolean {
  return publicPaths.some((p) => path === p || path.startsWith(p.endsWith('/') ? p : `${p}/`));
}

export async function signDemoToken(
  auth: AuthConfig,
  claims: { sub?: string; role?: string } = {},
): Promise<string> {
  const secret = new TextEncoder().encode(auth.jwtSecret);
  return new SignJWT({ role: claims.role ?? 'demo' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(auth.jwtIssuer)
    .setSubject(claims.sub ?? 'demo-user')
    .setIssuedAt()
    .setExpirationTime('2h')
    .sign(secret);
}

export async function verifyDemoToken(auth: AuthConfig, token: string) {
  const secret = new TextEncoder().encode(auth.jwtSecret);
  return jwtVerify(token, secret, { issuer: auth.jwtIssuer });
}

export function registerAuthRoutes(app: FastifyInstance, config: ServerConfig) {
  app.post('/auth/token', async (req, reply) => {
    const body = (req.body ?? {}) as { sub?: string; role?: string };
    const token = await signDemoToken(config.auth, body);
    return reply.send({
      access_token: token,
      token_type: 'Bearer',
      expires_in: 7200,
      hint: 'Send header: Authorization: Bearer <access_token>',
    });
  });

  app.get('/auth/me', async (req, reply) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return reply.code(401).send({ error: 'Missing Bearer token' });
    }
    try {
      const { payload } = await verifyDemoToken(config.auth, header.slice(7));
      return reply.send({ authenticated: true, payload });
    } catch {
      return reply.code(401).send({ error: 'Invalid token' });
    }
  });
}

export function registerJwtGuard(app: FastifyInstance, config: ServerConfig) {
  if (!config.auth.requireAuth && !config.auth.jwtEnabled) return;

  app.addHook('onRequest', async (req: FastifyRequest, reply: FastifyReply) => {
    if (!config.auth.requireAuth) return;

    const path = req.url.split('?')[0];
    if (isPublicPath(path, config.auth.publicPaths)) return;
    if (req.method === 'OPTIONS') return;

    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return reply.code(401).send({
        error: 'Unauthorized',
        hint: 'POST /auth/token to get a JWT, then send Authorization: Bearer <token>',
      });
    }

    try {
      await verifyDemoToken(config.auth, header.slice(7));
    } catch {
      return reply.code(401).send({ error: 'Invalid or expired JWT' });
    }
  });
}
