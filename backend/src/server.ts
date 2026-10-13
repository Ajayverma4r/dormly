// server.ts
import { env } from '@config/env';
import { readRuntimeFlags } from '@config/runtime-flags';
import {
  describeStartupError,
  prepareDatabase,
  startBackgroundJobs,
} from '@shared/startup/startup';
import { createApp } from './app';

async function main() {
  const flags = readRuntimeFlags();
  try {
    await prepareDatabase(flags);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(`[startup] ${describeStartupError(err)}`);
    process.exit(1);
  }

  const app = createApp();
  app.listen(env.port, () => {
    // eslint-disable-next-line no-console
    console.log(`Dormly backend listening on port ${env.port}`);
    startBackgroundJobs(flags);
  });
}

void main();
