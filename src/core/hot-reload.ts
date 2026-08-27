import { watch } from 'chokidar';
import { loadAppConfig } from '../config/loader.js';
import type { MockEngine } from './engine.js';
import type { Logger } from '../utils/logger.js';

export function startMockHotReload(
  mocksDir: string,
  engine: MockEngine,
  logger: Logger,
): void {
  const watcher = watch(mocksDir, {
    ignoreInitial: true,
    awaitWriteFinish: { stabilityThreshold: 200 },
  });

  const reload = (path: string) => {
    try {
      engine.reload(loadAppConfig(mocksDir));
      logger.info({ path }, 'Mock config reloaded');
    } catch (err) {
      logger.error({ err, path }, 'Failed to reload mock config');
    }
  };

  watcher.on('change', reload);
  watcher.on('add', reload);
  watcher.on('unlink', reload);
  logger.info({ mocksDir }, 'Watching mocks for hot-reload');
}
