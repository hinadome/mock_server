import type { AuthConfig, ServerConfig, TlsConfig } from '../core/types.js';

function loadTlsConfig(): TlsConfig {
  const certPath = process.env.TLS_CERT;
  const keyPath = process.env.TLS_KEY;
  const enabled = process.env.TLS_ENABLED === '1' || Boolean(certPath && keyPath);
  return {
    enabled,
    certPath,
    keyPath,
    caPath: process.env.TLS_CA,
    requestClientCert: process.env.TLS_MTLS === '1',
  };
}

function loadAuthConfig(): AuthConfig {
  const jwtSecret = process.env.JWT_SECRET ?? 'mock-server-dev-secret-change-me';
  const requireAuth = process.env.AUTH_REQUIRED === '1';
  const publicPaths = (process.env.AUTH_PUBLIC_PATHS ?? '/,/health,/api/discovery,/auth/token,/graphql/demo,/http/demo,/http-stream,/docs')
    .split(',')
    .map((p) => p.trim())
    .filter(Boolean);

  return {
    jwtEnabled: process.env.JWT_ENABLED === '1' || requireAuth,
    jwtSecret,
    jwtIssuer: process.env.JWT_ISSUER ?? 'mock-server',
    requireAuth,
    publicPaths,
  };
}

export function loadServerConfig(): ServerConfig {
  const corsRaw = process.env.CORS_ORIGINS ?? '*';
  const corsOrigins =
    corsRaw === '*' ? ['*'] : corsRaw.split(',').map((o) => o.trim()).filter(Boolean);

  return {
    host: process.env.HOST ?? '0.0.0.0',
    publicUrl: process.env.PUBLIC_URL,
    corsOrigins,
    httpPort: parseInt(process.env.HTTP_PORT ?? '3000', 10),
    wsPort: parseInt(process.env.WS_PORT ?? '3001', 10),
    grpcPort: parseInt(process.env.GRPC_PORT ?? '50051', 10),
    mqttPort: parseInt(process.env.MQTT_PORT ?? '1883', 10),
    mocksDir: process.env.MOCKS_DIR ?? './mocks',
    logLevel: process.env.LOG_LEVEL ?? 'info',
    inspectorMax: parseInt(process.env.INSPECTOR_MAX ?? '100', 10),
    tls: loadTlsConfig(),
    auth: loadAuthConfig(),
  };
}
