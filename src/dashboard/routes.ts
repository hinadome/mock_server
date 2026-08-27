import type { FastifyInstance } from 'fastify';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadDashboardHtml(): string {
  const candidates = [
    join(process.cwd(), 'src/dashboard/templates/dashboard.html'),
    join(__dirname, 'templates', 'dashboard.html'),
  ];
  for (const path of candidates) {
    if (existsSync(path)) return readFileSync(path, 'utf-8');
  }
  throw new Error('dashboard.html not found');
}

export function registerDashboard(app: FastifyInstance) {
  const html = loadDashboardHtml();

  app.get('/', async (_req, reply) => {
    reply.type('text/html').send(html);
  });

  app.get('/docs/protocols/:name', async (req, reply) => {
    const { name } = req.params as { name: string };
    const allowed = ['http', 'http-stream', 'websocket', 'sse', 'graphql', 'grpc', 'mqtt'];
    if (!allowed.includes(name)) {
      return reply.code(404).send({ error: 'Unknown protocol guide' });
    }
    const docName = name === 'http-stream' ? 'http-stream' : name;
    const docPath = join(process.cwd(), 'docs', 'protocols', `${docName}.md`);
    if (!existsSync(docPath)) {
      return reply.code(404).send({ error: 'Guide not found' });
    }
    const doc = readFileSync(docPath, 'utf-8');
    reply.type('text/plain').send(doc);
  });
}
