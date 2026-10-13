// config/db.ts
import { Pool, PoolClient } from 'pg';

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false,
  },
});

export async function query<T = any>(text: string, params?: any[]): Promise<T[]> {
  const result = await pool.query(text, params);
  return result.rows as T[];
}

export type TxQuery = <T = any>(text: string, params?: any[]) => Promise<T[]>;

/** Runs [fn] in one transaction on a single connection; rolls back on throw. */
export async function withTransaction<R>(fn: (q: TxQuery) => Promise<R>): Promise<R> {
  const client: PoolClient = await pool.connect();
  const q: TxQuery = async (text, params) =>
    (await client.query(text, params)).rows as any[];
  try {
    await client.query('BEGIN');
    const result = await fn(q);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw err;
  } finally {
    client.release();
  }
}