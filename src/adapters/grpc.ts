import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import { ReflectionService } from '@grpc/reflection';
import { join } from 'node:path';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import type { MockEngine } from '../core/engine.js';
import type { Logger } from '../utils/logger.js';
import type { ServerConfig } from '../core/types.js';

const DEMO_PROTO = `
syntax = "proto3";
package demo;

service DemoService {
  rpc Ping (PingRequest) returns (PingReply);
  rpc StreamPings (PingRequest) returns (stream PingReply);
  rpc CollectPings (stream PingRequest) returns (PingReply);
  rpc Chat (stream PingRequest) returns (stream PingReply);
}

message PingRequest {
  string message = 1;
}

message PingReply {
  string message = 1;
  string protocol = 2;
}
`;

type PingRequest = { message?: string };
type PingReply = { message: string; protocol: string };

function buildServerCredentials(config: ServerConfig): grpc.ServerCredentials {
  if (!config.tls.enabled || !config.tls.certPath || !config.tls.keyPath) {
    return grpc.ServerCredentials.createInsecure();
  }
  if (!existsSync(config.tls.certPath) || !existsSync(config.tls.keyPath)) {
    return grpc.ServerCredentials.createInsecure();
  }

  const rootCerts =
    config.tls.caPath && existsSync(config.tls.caPath)
      ? readFileSync(config.tls.caPath)
      : null;
  const keyCertPairs = [
    {
      private_key: readFileSync(config.tls.keyPath),
      cert_chain: readFileSync(config.tls.certPath),
    },
  ];
  const checkClientCertificate = config.tls.requestClientCert;
  return grpc.ServerCredentials.createSsl(rootCerts, keyCertPairs, checkClientCertificate);
}

export async function startGrpcServer(
  config: ServerConfig,
  engine: MockEngine,
  logger: Logger,
): Promise<grpc.Server> {
  const protoPath = join(config.mocksDir, 'grpc', 'demo.proto');
  const grpcDir = join(config.mocksDir, 'grpc');
  if (!existsSync(grpcDir)) mkdirSync(grpcDir, { recursive: true });
  writeFileSync(protoPath, DEMO_PROTO.trim());

  const packageDefinition = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });

  const demoProto = grpc.loadPackageDefinition(packageDefinition) as unknown as {
    demo: {
      DemoService: {
        service: grpc.ServiceDefinition;
      };
    };
  };

  const server = new grpc.Server();

  server.addService(demoProto.demo.DemoService.service, {
    Ping: async (
      call: grpc.ServerUnaryCall<PingRequest, PingReply>,
      callback: grpc.sendUnaryData<PingReply>,
    ) => {
      const response = await engine.handle({
        protocol: 'grpc',
        method: 'Ping',
        path: 'DemoService/Ping',
        body: call.request,
        clientIp: call.getPeer(),
      });

      const body = response.body as Partial<PingReply> | undefined;
      callback(null, {
        message: body?.message ?? `Pong: ${call.request.message ?? 'hello'}`,
        protocol: body?.protocol ?? 'grpc — unary',
      });
    },

    StreamPings: async (call: grpc.ServerWritableStream<PingRequest, PingReply>) => {
      const response = await engine.handle({
        protocol: 'grpc',
        method: 'StreamPings',
        path: 'DemoService/StreamPings',
        body: call.request,
        clientIp: call.getPeer(),
      });

      const chunks =
        (response.stream as PingReply[] | undefined) ??
        [
          { message: `stream-1: ${call.request.message ?? 'hello'}`, protocol: 'grpc' },
          { message: `stream-2: ${call.request.message ?? 'hello'}`, protocol: 'grpc' },
          { message: `stream-3: ${call.request.message ?? 'hello'}`, protocol: 'grpc' },
        ];

      for (const chunk of chunks) {
        call.write({ message: chunk.message, protocol: chunk.protocol ?? 'grpc' });
        await new Promise((r) => setTimeout(r, 200));
      }
      call.end();
    },

    CollectPings: (
      call: grpc.ServerReadableStream<PingRequest, PingReply>,
      callback: grpc.sendUnaryData<PingReply>,
    ) => {
      const messages: string[] = [];

      call.on('data', (req: PingRequest) => {
        messages.push(req.message ?? '');
      });

      call.on('end', async () => {
        const response = await engine.handle({
          protocol: 'grpc',
          method: 'CollectPings',
          path: 'DemoService/CollectPings',
          body: { messages },
          clientIp: call.getPeer(),
        });
        const body = response.body as Partial<PingReply> | undefined;
        callback(null, {
          message:
            body?.message ??
            `Collected ${messages.length} messages: [${messages.join(', ')}]`,
          protocol: body?.protocol ?? 'grpc — client streaming',
        });
      });

      call.on('error', (err) => {
        callback(err, null);
      });
    },

    Chat: (call: grpc.ServerDuplexStream<PingRequest, PingReply>) => {
      void engine.handle({
        protocol: 'grpc',
        method: 'Chat',
        path: 'DemoService/Chat',
        body: { started: true },
        clientIp: call.getPeer(),
      });

      call.write({
        message: 'Chat started — send messages, get echoes',
        protocol: 'grpc — bidirectional streaming',
      });

      call.on('data', (req: PingRequest) => {
        call.write({
          message: `echo: ${req.message ?? ''}`,
          protocol: 'grpc — bidirectional streaming',
        });
      });

      call.on('end', () => {
        call.write({ message: 'Chat ended', protocol: 'grpc — bidirectional streaming' });
        call.end();
      });
    },
  });

  const reflection = new ReflectionService(packageDefinition);
  reflection.addToServer(server);

  const credentials = buildServerCredentials(config);
  await new Promise<void>((resolve, reject) => {
    server.bindAsync(`${config.host}:${config.grpcPort}`, credentials, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });

  logger.info(
    {
      port: config.grpcPort,
      host: config.host,
      tls: config.tls.enabled,
      mtls: config.tls.requestClientCert,
    },
    'gRPC server listening',
  );
  return server;
}
