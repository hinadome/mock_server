import type { FastifyInstance } from 'fastify';
import type { ServerConfig, AdapterStatus } from '../core/types.js';
import { buildBaseUrl, buildHostForClients, buildWsUrl, getLanIp } from '../utils/network.js';

export function registerDiscoveryRoutes(
  app: FastifyInstance,
  config: ServerConfig,
  statuses: () => AdapterStatus[],
) {
  app.get('/api/discovery', async () => {
    const clientHost = buildHostForClients(config.host, config.publicUrl);
    const httpBase = buildBaseUrl(config.host, config.httpPort, config.publicUrl);
    const wsBase = buildWsUrl(config.host, config.wsPort, config.publicUrl);

    return {
      host: clientHost,
      lanIp: getLanIp(),
      pathPattern: '/{protocol}/{name}',
      protocols: {
        http: {
          url: `${httpBase}/http/demo`,
          example: `curl ${httpBase}/http/demo`,
        },
        httpStream: {
          url: `${httpBase}/http-stream/demo`,
          example: `curl -N ${httpBase}/http-stream/demo`,
          fetchExample: `fetch('${httpBase}/http-stream/demo').then(async (r) => { const reader = r.body.getReader(); const dec = new TextDecoder(); for (;;) { const { done, value } = await reader.read(); if (done) break; console.log(dec.decode(value)); } })`,
        },
        websocket: {
          url: `${wsBase}/ws/demo`,
          example: `wscat -c ${wsBase}/ws/demo`,
        },
        sse: {
          url: `${httpBase}/sse/demo`,
          example: `curl -N ${httpBase}/sse/demo`,
        },
        graphql: {
          url: `${httpBase}/graphql/demo`,
          playground: `${httpBase}/graphql`,
          example: `curl ${httpBase}/graphql/demo`,
        },
        grpc: {
          url: `${httpBase}/grpc/demo`,
          host: clientHost,
          port: config.grpcPort,
          reflection: true,
          example: `curl ${httpBase}/grpc/demo`,
        },
        mqtt: {
          host: clientHost,
          port: config.mqttPort,
          exampleTopic: 'mqtt/demo',
          example: `mosquitto_pub -h ${clientHost} -p ${config.mqttPort} -t mqtt/demo -m '{"message":"hi"}'`,
        },
      },
      adapters: statuses(),
    };
  });
}
