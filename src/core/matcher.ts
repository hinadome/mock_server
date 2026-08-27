import type { MockRequest, MockRoute } from './types.js';

function matchPath(pattern: string, path: string): Record<string, string> | null {
  const patternParts = pattern.split('/').filter(Boolean);
  const pathParts = path.split('/').filter(Boolean);
  if (patternParts.length !== pathParts.length) return null;

  const params: Record<string, string> = {};
  for (let i = 0; i < patternParts.length; i++) {
    const pp = patternParts[i];
    const vp = pathParts[i];
    if (pp.startsWith(':')) {
      params[pp.slice(1)] = decodeURIComponent(vp);
    } else if (pp !== vp) {
      return null;
    }
  }
  return params;
}

function matchTopic(pattern: string, topic: string): Record<string, string> | null {
  const patternParts = pattern.split('/');
  const topicParts = topic.split('/');
  if (patternParts.length !== topicParts.length) return null;

  const params: Record<string, string> = {};
  for (let i = 0; i < patternParts.length; i++) {
    const pp = patternParts[i];
    const tp = topicParts[i];
    if (pp === '+') continue;
    if (pp === '#') return params;
    if (pp.startsWith(':')) {
      params[pp.slice(1)] = tp;
    } else if (pp !== tp) {
      return null;
    }
  }
  return params;
}

export function findMatchingRoute(
  routes: MockRoute[],
  req: MockRequest,
): { route: MockRoute; params: Record<string, string> } | null {
  for (const route of routes) {
    const { match } = route;

    if (match.method && req.method && match.method.toUpperCase() !== req.method.toUpperCase()) {
      continue;
    }

    if (match.path && req.path) {
      const params = matchPath(match.path, req.path);
      if (params) return { route, params };
      continue;
    }

    if (match.topic && req.topic) {
      const params = matchTopic(match.topic, req.topic);
      if (params) return { route, params };
      continue;
    }

    if (match.operation && req.path === match.operation) {
      return { route, params: {} };
    }

    if (match.service && match.grpcMethod && req.path === `${match.service}/${match.grpcMethod}`) {
      return { route, params: {} };
    }

    if (!match.path && !match.topic && !match.operation && !match.service) {
      return { route, params: {} };
    }
  }
  return null;
}

export function describeRoute(route: MockRoute): string {
  const m = route.match;
  if (m.method && m.path) return `${m.method} ${m.path}`;
  if (m.topic) return `topic:${m.topic}`;
  if (m.operation) return `graphql:${m.operation}`;
  if (m.service && m.grpcMethod) return `grpc:${m.service}/${m.grpcMethod}`;
  return route.description ?? 'unknown';
}
