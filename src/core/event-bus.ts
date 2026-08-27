import { EventEmitter } from 'node:events';
import type { MockRequest, MockResponse } from './types.js';

export type BusEvents = {
  publish: { topic: string; payload: unknown };
};

export type EventBus = EventEmitter<{ publish: [BusEvents['publish']] }>;

export function createEventBus(): EventBus {
  return new EventEmitter<{ publish: [BusEvents['publish']] }>();
}

export function normalizeEmitTopics(emit: string | string[] | undefined): string[] {
  if (!emit) return [];
  return Array.isArray(emit) ? emit : [emit];
}

export function publishFromResponse(
  bus: EventBus,
  response: MockResponse,
  payload: unknown,
): void {
  for (const topic of normalizeEmitTopics(response.emit)) {
    bus.emit('publish', { topic, payload });
  }
}

export async function delay(ms: number | undefined): Promise<void> {
  if (!ms || ms <= 0) return;
  await new Promise((resolve) => setTimeout(resolve, ms));
}

export function buildMockRequest(
  partial: Omit<MockRequest, 'protocol'> & { protocol?: MockRequest['protocol'] },
): MockRequest {
  return { ...partial, protocol: partial.protocol ?? 'http' };
}
