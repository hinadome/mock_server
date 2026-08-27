import { z } from 'zod';

export const mockResponseSchema = z.object({
  status: z.number().optional(),
  headers: z.record(z.string(), z.string()).optional(),
  body: z.unknown().optional(),
  delayMs: z.number().optional(),
  chunkDelayMs: z.number().optional(),
  error: z.object({ code: z.string(), message: z.string() }).optional(),
  stream: z.array(z.unknown()).optional(),
  keepOpen: z.boolean().optional(),
  emit: z.union([z.string(), z.array(z.string())]).optional(),
});

export const routeSchema = z.object({
  match: z.object({
    method: z.string().optional(),
    path: z.string().optional(),
    topic: z.string().optional(),
    operation: z.string().optional(),
    service: z.string().optional(),
    grpcMethod: z.string().optional(),
  }),
  response: mockResponseSchema,
  description: z.string().optional(),
});

export const protocolConfigSchema = z.object({
  routes: z.array(routeSchema).default([]),
});

export const unifiedConfigSchema = z.object({
  http: protocolConfigSchema.optional(),
  httpStream: protocolConfigSchema.optional(),
  websocket: protocolConfigSchema.optional(),
  sse: protocolConfigSchema.optional(),
  graphql: protocolConfigSchema.optional(),
  grpc: protocolConfigSchema.optional(),
  mqtt: protocolConfigSchema.optional(),
});
