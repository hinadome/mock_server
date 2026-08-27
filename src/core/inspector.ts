import { randomUUID } from 'node:crypto';
import type { InspectorEntry } from './types.js';

export class RequestInspector {
  private entries: InspectorEntry[] = [];
  private max: number;

  constructor(max: number) {
    this.max = max;
  }

  record(entry: Omit<InspectorEntry, 'id' | 'timestamp'>): InspectorEntry {
    const full: InspectorEntry = {
      ...entry,
      id: randomUUID(),
      timestamp: new Date().toISOString(),
    };
    this.entries.unshift(full);
    if (this.entries.length > this.max) {
      this.entries.length = this.max;
    }
    return full;
  }

  list(): InspectorEntry[] {
    return [...this.entries];
  }
}
