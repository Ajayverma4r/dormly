// server.ts
import { env } from '@config/env';
import { readRuntimeFlags } from '@config/runtime-flags';
import {
  describeStartupError,
  prepareDatabase,
  startBackgroundJobs,
} from '@shared/startup/startup';
import { fileStorage } from '@shared/storage/file-storage';
import { createApp } from './app';

async function main() {
  const flags = readRuntimeFlags();
  try {
    const storage = fileStorage();
    // eslint-disable-next-line no-console
    console.log(`[startup] file storage: ${storage.kind}`);
    if (storage.kind === 'local' && env.nodeEnv === 'production') {
      // eslint-disable-next-line no-console
      console.warn(
        '[startup] Uploads are on local disk and will be lost on redeploy. ' +
          'Set FILE_STORAGE_DRIVER=supabase.',
      );
    }
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
