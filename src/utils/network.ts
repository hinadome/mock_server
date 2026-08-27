import { networkInterfaces } from 'node:os';

export function getLanIp(): string | undefined {
  const nets = networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] ?? []) {
      if (net.family === 'IPv4' && !net.internal) {
        return net.address;
      }
    }
  }
  return undefined;
}

export function buildBaseUrl(host: string, port: number, publicUrl?: string): string {
  if (publicUrl) return publicUrl.replace(/\/$/, '');
  const displayHost = host === '0.0.0.0' ? 'localhost' : host;
  return `http://${displayHost}:${port}`;
}

export function buildWsUrl(host: string, port: number, publicUrl?: string): string {
  if (publicUrl) {
    const u = new URL(publicUrl);
    u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
    u.port = String(port);
    return u.origin;
  }
  const displayHost = host === '0.0.0.0' ? 'localhost' : host;
  return `ws://${displayHost}:${port}`;
}

export function buildHostForClients(host: string, publicUrl?: string): string {
  if (publicUrl) {
    try {
      return new URL(publicUrl).hostname;
    } catch {
      /* fall through */
    }
  }
  if (host !== '0.0.0.0') return host;
  return getLanIp() ?? 'localhost';
}
