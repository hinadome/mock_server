import { Aedes } from 'aedes';
import { createServer as createNetServer } from 'node:net';
import type { MockEngine } from '../core/engine.js';
import type { EventBus } from '../core/event-bus.js';
import type { Logger } from '../utils/logger.js';

function publish(broker: Aedes, topic: string, payload: unknown): void {
  broker.publish(
    {
      cmd: 'publish',
      topic,
      payload: Buffer.from(JSON.stringify(payload)),
      qos: 0,
      retain: false,
      dup: false,
    },
    () => {},
  );
}

export async function startMqttBroker(
  config: { host: string; mqttPort: number },
  engine: MockEngine,
  bus: EventBus,
  logger: Logger,
): Promise<{ broker: Aedes; server: ReturnType<typeof createNetServer> }> {
  const broker = new Aedes();

  broker.on('publish', async (packet, client) => {
    if (!client || !packet.topic) return;
    if (packet.topic.startsWith('$')) return;

    const response = await engine.handle({
      protocol: 'mqtt',
      method: 'PUBLISH',
      topic: packet.topic,
      body: packet.payload?.toString(),
    });

    const replyTopic = response.headers?.['reply-topic'];
    if (replyTopic) {
      publish(broker, replyTopic, response.body ?? {});
    }

    if (packet.topic === 'mqtt/demo') {
      publish(broker, 'mqtt/demo/response', {
        message: 'MQTT demo — lightweight pub/sub messaging',
        protocol: 'mqtt',
        topic: 'mqtt/demo',
        received: packet.payload?.toString(),
      });
    }
  });

  bus.on('publish', (event: { topic: string; payload: unknown }) => {
    publish(broker, event.topic, event.payload);
  });

  const server = createNetServer(broker.handle);
  await new Promise<void>((resolve) => {
    server.listen(config.mqttPort, config.host, resolve);
  });

  logger.info({ port: config.mqttPort, host: config.host }, 'MQTT broker listening');
  return { broker, server };
}
