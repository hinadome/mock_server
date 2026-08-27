import type { FastifyInstance } from 'fastify';
import type { RequestInspector } from '../core/inspector.js';
import type { AdapterStatus } from '../core/types.js';

export function registerInspectorRoutes(app: FastifyInstance, inspector: RequestInspector) {
  app.get('/api/requests', async () => ({
    count: inspector.list().length,
    requests: inspector.list(),
  }));
}

export function registerHealthRoute(app: FastifyInstance, statuses: () => AdapterStatus[]) {
  app.get('/health', async () => ({
    status: 'ok',
    adapters: statuses(),
  }));
}
