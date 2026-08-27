import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parse as parseYaml } from 'yaml';
import type { AppConfig, MockRoute } from '../core/types.js';
import { protocolConfigSchema, unifiedConfigSchema } from './schema.js';

function loadYamlFile(path: string): { routes: MockRoute[] } {
  if (!existsSync(path)) return { routes: [] };
  const raw = readFileSync(path, 'utf-8');
  const parsed = parseYaml(raw);
  return protocolConfigSchema.parse(parsed ?? {});
}

function loadGrpcRoutes(mocksDir: string): MockRoute[] {
  const routesFile = join(mocksDir, 'grpc', 'routes.yaml');
  if (existsSync(routesFile)) {
    return loadYamlFile(routesFile).routes;
  }
  return [];
}

function mergeRoutes(base: MockRoute[], extra: MockRoute[] | undefined): MockRoute[] {
  if (!extra?.length) return base;
  return [...base, ...extra];
}

export function loadAppConfig(mocksDir: string): AppConfig {
  const perFile: AppConfig = {
    http: loadYamlFile(join(mocksDir, 'http.yaml')),
    httpStream: loadYamlFile(join(mocksDir, 'http-stream.yaml')),
    websocket: loadYamlFile(join(mocksDir, 'websocket.yaml')),
    sse: loadYamlFile(join(mocksDir, 'sse.yaml')),
    graphql: loadYamlFile(join(mocksDir, 'graphql', 'routes.yaml')),
    grpc: { routes: loadGrpcRoutes(mocksDir) },
    mqtt: loadYamlFile(join(mocksDir, 'mqtt.yaml')),
  };

  const unifiedPath = join(mocksDir, 'config.yaml');
  if (!existsSync(unifiedPath)) return perFile;

  const unified = unifiedConfigSchema.parse(parseYaml(readFileSync(unifiedPath, 'utf-8')) ?? {});
  return {
    http: { routes: mergeRoutes(perFile.http.routes, unified.http?.routes) },
    httpStream: { routes: mergeRoutes(perFile.httpStream.routes, unified.httpStream?.routes) },
    websocket: { routes: mergeRoutes(perFile.websocket.routes, unified.websocket?.routes) },
    sse: { routes: mergeRoutes(perFile.sse.routes, unified.sse?.routes) },
    graphql: { routes: mergeRoutes(perFile.graphql.routes, unified.graphql?.routes) },
    grpc: { routes: mergeRoutes(perFile.grpc.routes, unified.grpc?.routes) },
    mqtt: { routes: mergeRoutes(perFile.mqtt.routes, unified.mqtt?.routes) },
  };
}

export function listProtoFiles(mocksDir: string): string[] {
  const grpcDir = join(mocksDir, 'grpc');
  if (!existsSync(grpcDir)) return [];
  return readdirSync(grpcDir).filter((f) => f.endsWith('.proto'));
}

export function loadGraphqlSchema(mocksDir: string): string {
  const schemaPath = join(mocksDir, 'graphql', 'schema.graphql');
  if (!existsSync(schemaPath)) {
    return `type Query {
  demo: String!
  hello(name: String): String!
}`;
  }
  return readFileSync(schemaPath, 'utf-8');
}
