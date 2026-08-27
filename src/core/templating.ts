import type { MockRequest } from './types.js';

function getByPath(obj: unknown, path: string): unknown {
  const parts = path.split('.');
  let current: unknown = obj;
  for (const part of parts) {
    if (current == null || typeof current !== 'object') return undefined;
    current = (current as Record<string, unknown>)[part];
  }
  return current;
}

export function applyTemplate(value: unknown, req: MockRequest): unknown {
  if (typeof value === 'string') {
    return value.replace(/\{\{([^}]+)\}\}/g, (_, expr: string) => {
      const trimmed = expr.trim();
      if (trimmed.startsWith('params.')) {
        const v = req.params?.[trimmed.slice(7)];
        return v != null ? String(v) : '';
      }
      if (trimmed.startsWith('query.')) {
        const v = req.query?.[trimmed.slice(6)];
        return v != null ? String(v) : '';
      }
      if (trimmed.startsWith('req.body.')) {
        const v = getByPath(req.body, trimmed.slice(9));
        return v != null ? String(v) : '';
      }
      if (trimmed === 'req.clientIp') {
        return req.clientIp ?? '';
      }
      return '';
    });
  }
  if (Array.isArray(value)) {
    return value.map((v) => applyTemplate(v, req));
  }
  if (value != null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = applyTemplate(v, req);
    }
    return out;
  }
  return value;
}
