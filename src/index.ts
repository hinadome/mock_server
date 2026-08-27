import { WebSocketServer } from 'ws';
import { loadServerConfig } from './config/env.js';
import { loadAppConfig, loadGraphqlSchema } from './config/loader.js';
import { createEventBus } from './core/event-bus.js';
import { createMockEngine } from './core/engine.js';
import { createHttpServer, registerHttpMockRoutes, startHttpServer } from './adapters/http.js';
import { registerHttpStreamRoutes } from './adapters/http-stream.js';
import { registerSseRoutes } from './adapters/sse.js';
import { startStandaloneWsServer } from './adapters/websocket.js';
import { attachGraphqlWs, registerGraphqlRoutes } from './adapters/graphql.js';
import { startGrpcServer } from './adapters/grpc.js';
import { registerGrpcHttpRoutes } from './adapters/grpc-http.js';
import { startMqttBroker } from './adapters/mqtt.js';
import {
  registerDiscoveryRoutes,
  registerHealthRoute,
  registerInspectorRoutes,
} from './api/routes.js';
import { registerDashboard } from './dashboard/routes.js';
import { registerAuthRoutes, registerJwtGuard } from './auth/jwt.js';
import { createLogger } from './utils/logger.js';
import { buildBaseUrl, buildHostForClients, buildWsUrl, getLanIp } from './utils/network.js';
import { startMockHotReload } from './core/hot-reload.js';
import type { AdapterStatus } from './core/types.js';

async function main() {
  const config = loadServerConfig();
  const logger = createLogger(config.logLevel);
  const appConfig = loadAppConfig(config.mocksDir);
  const bus = createEventBus();
  const { engine, inspector } = createMockEngine(appConfig, bus, config);
  const schemaSdl = loadGraphqlSchema(config.mocksDir);

  const statuses: AdapterStatus[] = [
    { name: 'http', running: false },
    { name: 'httpStream', running: false },
    { name: 'websocket', running: false },
    { name: 'sse', running: false },
    { name: 'graphql', running: false },
    { name: 'grpc', running: false },
    { name: 'mqtt', running: false },
  ];

  const getStatuses = () => statuses;

  const httpApp = await createHttpServer(config);
  registerJwtGuard(httpApp, config);
  registerAuthRoutes(httpApp, config);
  registerDashboard(httpApp);
  registerDiscoveryRoutes(httpApp, config, getStatuses);
  registerInspectorRoutes(httpApp, inspector);
  registerHealthRoute(httpApp, getStatuses);
  registerSseRoutes(httpApp, engine, bus);
  registerHttpStreamRoutes(httpApp, engine, bus);
  const { schema } = registerGraphqlRoutes(httpApp, engine, schemaSdl, bus);
  registerGrpcHttpRoutes(httpApp, engine);
  registerHttpMockRoutes(httpApp, engine);

  await startHttpServer(httpApp, config, logger);

  // GraphQL subscriptions over WebSocket (graphql-ws on /graphql)
  const gqlWss = new WebSocketServer({ server: httpApp.server, path: '/graphql' });
  attachGraphqlWs(gqlWss, schema);

  statuses.find((s) => s.name === 'http')!.running = true;
  statuses.find((s) => s.name === 'http')!.url = buildBaseUrl(config.host, config.httpPort, config.publicUrl);
  statuses.find((s) => s.name === 'httpStream')!.running = true;
  statuses.find((s) => s.name === 'sse')!.running = true;
  statuses.find((s) => s.name === 'graphql')!.running = true;

  await startStandaloneWsServer(config, engine, bus, logger);
  statuses.find((s) => s.name === 'websocket')!.running = true;
  statuses.find((s) => s.name === 'websocket')!.url = buildWsUrl(config.host, config.wsPort, config.publicUrl);

  await startGrpcServer(config, engine, logger);
  statuses.find((s) => s.name === 'grpc')!.running = true;
  statuses.find((s) => s.name === 'grpc')!.url = `${buildHostForClients(config.host, config.publicUrl)}:${config.grpcPort}`;

  await startMqttBroker(config, engine, bus, logger);
  statuses.find((s) => s.name === 'mqtt')!.running = true;
  statuses.find((s) => s.name === 'mqtt')!.url = `${buildHostForClients(config.host, config.publicUrl)}:${config.mqttPort}`;

  if (process.env.HOT_RELOAD !== '0') {
    startMockHotReload(config.mocksDir, engine, logger);
  }

  const clientHost = buildHostForClients(config.host, config.publicUrl);
  const scheme = config.tls.enabled && config.tls.certPath ? 'https' : 'http';
  const httpUrl =
    config.publicUrl?.replace(/\/$/, '') ??
    `${scheme}://${config.host === '0.0.0.0' ? 'localhost' : config.host}:${config.httpPort}`;
  const lanIp = getLanIp();

  logger.info('Mock server ready');
  logger.info(`  Dashboard:  ${httpUrl}/`);
  logger.info(`  HTTP:       ${httpUrl}/http/demo`);
  logger.info(`  HTTP Stream: ${httpUrl}/http-stream/demo  (Fetch ReadableStream)`);
  logger.info(`  WebSocket:  ${buildWsUrl(config.host, config.wsPort, config.publicUrl)}/ws/demo`);
  logger.info(`  SSE:        ${httpUrl}/sse/demo`);
  logger.info(`  GraphQL:    ${httpUrl}/graphql  (subscriptions via graphql-ws)`);
  logger.info(`  gRPC:       ${httpUrl}/grpc/demo  (also ${clientHost}:${config.grpcPort})`);
  logger.info(`  MQTT:       mqtt/demo on ${clientHost}:${config.mqttPort}`);
  if (config.auth.jwtEnabled || config.auth.requireAuth) {
    logger.info(`  Auth:       POST ${httpUrl}/auth/token  (JWT ${config.auth.requireAuth ? 'REQUIRED' : 'available'})`);
  }
  if (config.tls.enabled) {
    logger.info(`  TLS:        enabled${config.tls.requestClientCert ? ' (mTLS)' : ''}`);
  }
  if (lanIp) {
    logger.info(`  LAN IP:     ${lanIp} (external clients can use this host)`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
