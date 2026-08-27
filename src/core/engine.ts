import type { AppConfig, MockRequest, MockResponse, Protocol, ServerConfig } from './types.js';
import { describeRoute, findMatchingRoute } from './matcher.js';
import { applyTemplate } from './templating.js';
import type { EventBus } from './event-bus.js';
import { delay, publishFromResponse } from './event-bus.js';
import { RequestInspector } from './inspector.js';

export { RequestInspector } from './inspector.js';

export class MockEngine {
  constructor(
    private config: AppConfig,
    private bus: EventBus,
    private inspector: RequestInspector,
  ) {}

  reload(config: AppConfig): void {
    this.config = config;
  }

  getRoutes(protocol: Protocol) {
    return this.config[protocol].routes;
  }

  async handle(req: MockRequest): Promise<MockResponse> {
    const routes = this.config[req.protocol].routes;
    const match = findMatchingRoute(routes, req);
    const reqWithParams = match ? { ...req, params: match.params } : req;

    let response: MockResponse;
    let matchedRoute: string | undefined;

    if (match) {
      matchedRoute = describeRoute(match.route);
      await delay(match.route.response.delayMs);
      response = {
        ...match.route.response,
        headers: applyTemplate(match.route.response.headers, reqWithParams) as
          | Record<string, string>
          | undefined,
        body: applyTemplate(match.route.response.body, reqWithParams),
        stream: applyTemplate(match.route.response.stream, reqWithParams) as unknown[] | undefined,
      };
    } else {
      response = {
        status: 404,
        body: {
          error: 'No mock route matched',
          protocol: req.protocol,
          method: req.method,
          path: req.path,
          topic: req.topic,
        },
      };
    }

    this.inspector.record({
      protocol: req.protocol,
      clientIp: req.clientIp,
      method: req.method,
      path: req.path,
      topic: req.topic,
      request: {
        headers: req.headers,
        query: req.query,
        body: req.body,
      },
      matchedRoute,
      response,
    });

    if (response.emit) {
      publishFromResponse(this.bus, response, response.body);
    }

    return response;
  }
}

export function createMockEngine(
  config: AppConfig,
  bus: EventBus,
  serverConfig: ServerConfig,
): { engine: MockEngine; inspector: RequestInspector } {
  const inspector = new RequestInspector(serverConfig.inspectorMax);
  const engine = new MockEngine(config, bus, inspector);
  return { engine, inspector };
}
