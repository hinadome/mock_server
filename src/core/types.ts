export type Protocol =
  | 'http'
  | 'httpStream'
  | 'websocket'
  | 'sse'
  | 'graphql'
  | 'grpc'
  | 'mqtt';

export interface MockRequest {
  protocol: Protocol;
  method?: string;
  path?: string;
  topic?: string;
  headers?: Record<string, string>;
  query?: Record<string, string>;
  body?: unknown;
  metadata?: Record<string, string>;
  clientIp?: string;
  params?: Record<string, string>;
}

export interface MockError {
  code: string;
  message: string;
}

export interface MockResponse {
  status?: number;
  headers?: Record<string, string>;
  body?: unknown;
  delayMs?: number;
  /** Delay between streamed chunks (HTTP Streams / gRPC). */
  chunkDelayMs?: number;
  error?: MockError;
  stream?: unknown[];
  /** Keep the HTTP Streams connection open after `stream` chunks (for bus events). */
  keepOpen?: boolean;
  emit?: string | string[];
}

export interface RouteMatch {
  method?: string;
  path?: string;
  topic?: string;
  operation?: string;
  service?: string;
  grpcMethod?: string;
}

export interface MockRoute {
  match: RouteMatch;
  response: MockResponse;
  description?: string;
}

export interface ProtocolConfig {
  routes: MockRoute[];
}

export interface AppConfig {
  http: ProtocolConfig;
  httpStream: ProtocolConfig;
  websocket: ProtocolConfig;
  sse: ProtocolConfig;
  graphql: ProtocolConfig;
  grpc: ProtocolConfig;
  mqtt: ProtocolConfig;
}

export interface TlsConfig {
  enabled: boolean;
  certPath?: string;
  keyPath?: string;
  caPath?: string;
  requestClientCert: boolean; // mTLS
}

export interface AuthConfig {
  jwtEnabled: boolean;
  jwtSecret: string;
  jwtIssuer: string;
  requireAuth: boolean;
  publicPaths: string[];
}

export interface ServerConfig {
  host: string;
  publicUrl?: string;
  corsOrigins: string[];
  httpPort: number;
  wsPort: number;
  grpcPort: number;
  mqttPort: number;
  mocksDir: string;
  logLevel: string;
  inspectorMax: number;
  tls: TlsConfig;
  auth: AuthConfig;
}

export interface InspectorEntry {
  id: string;
  timestamp: string;
  protocol: Protocol;
  clientIp?: string;
  method?: string;
  path?: string;
  topic?: string;
  request: {
    headers?: Record<string, string>;
    query?: Record<string, string>;
    body?: unknown;
  };
  matchedRoute?: string;
  response?: MockResponse;
}

export interface AdapterStatus {
  name: Protocol;
  running: boolean;
  url?: string;
}
