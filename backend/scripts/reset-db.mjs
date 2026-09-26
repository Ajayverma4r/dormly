// One-shot: wipe public schema, re-apply migrations + seeds.
// Usage: node scripts/reset-db.mjs
// Never logs DATABASE_URL.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
dotenv.config({ path: path.join(root, '.env') });

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL missing in backend/.env');
  process.exit(1);
}

const hostHint = (() => {
  try {
    return new URL(databaseUrl).hostname;
  } catch {
    return '(unparsed host)';
  }
})();

const migrationsDir = path.join(root, 'src/db/migrations');
const seedsDir = path.join(root, 'src/db/seeds');

function listSql(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => path.join(dir, f));
}

async function runFile(client, filePath) {
  const sql = fs.readFileSync(filePath, 'utf8');
  const name = path.basename(filePath);
  process.stdout.write(`  → ${name} ... `);
  await client.query(sql);
  console.log('ok');
}

async function main() {
  console.log(`Resetting database at host: ${hostHint}`);
  const client = new pg.Client({
    connectionString: databaseUrl,
    ssl: hostHint.includes('supabase')
      ? { rejectUnauthorized: false }
      : undefined,
  });
  await client.connect();

  try {
    console.log('Dropping public schema...');
    await client.query('DROP SCHEMA IF EXISTS public CASCADE');
    await client.query('CREATE SCHEMA public');
    await client.query('GRANT ALL ON SCHEMA public TO postgres');
    await client.query('GRANT ALL ON SCHEMA public TO public');
    await client.query('CREATE EXTENSION IF NOT EXISTS "pgcrypto"');

    console.log('Applying migrations...');
    for (const file of listSql(migrationsDir)) {
      await runFile(client, file);
    }

    console.log('Applying seeds...');
    for (const file of listSql(seedsDir)) {
      await runFile(client, file);
    }

    const { rows } = await client.query(
      `SELECT count(*)::int AS n FROM information_schema.tables
       WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`,
    );
    console.log(`Done. public tables: ${rows[0].n}`);
    console.log('Fresh start ready — clear the mobile app data and log in again.');
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error('Reset failed:', err.message);
  process.exit(1);
});
