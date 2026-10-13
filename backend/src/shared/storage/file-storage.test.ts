import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import express from 'express';
import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import type { Server } from 'http';
import type { AddressInfo } from 'net';

const PROPERTY_A = '11111111-1111-4111-8111-111111111111';
const PROPERTY_B = '22222222-2222-4222-8222-222222222222';
const TENANCY_A = '33333333-3333-4333-8333-333333333333';
const TENANCY_B = '44444444-4444-4444-8444-444444444444';
const DOC_A = '55555555-5555-4555-8555-555555555555';
const DOC_B = '66666666-6666-4666-8666-666666666666';

const tenancyProperty: Record<string, string> = {
  [TENANCY_A]: PROPERTY_A,
  [TENANCY_B]: PROPERTY_B,
};
const documents = [
  { id: DOC_A, tenancy_id: TENANCY_A, file_url: `/uploads/tenant-documents/${TENANCY_A}-doc-1.jpg` },
  { id: DOC_B, tenancy_id: TENANCY_B, file_url: `/uploads/tenant-documents/${TENANCY_B}-doc-1.jpg` },
];

vi.mock('@config/db', () => ({
  query: vi.fn(async (sql: string, params: unknown[] = []) => {
    if (sql.includes('FROM tenancies WHERE id = $1::uuid AND property_id')) {
      return tenancyProperty[params[0] as string] === params[1] ? [{ ok: 1 }] : [];
    }
    if (sql.includes('FROM tenant_documents WHERE id = $1::uuid AND tenancy_id')) {
      return documents
        .filter((d) => d.id === params[0] && d.tenancy_id === params[1])
        .map(({ id, file_url }) => ({ id, file_url }));
    }
    throw new Error(`unexpected query in file-storage tests: ${sql}`);
  }),
  withTransaction: vi.fn(async () => {
    throw new Error('transactions are not used by file-storage tests');
  }),
}));

import {
  LocalDiskStorage,
  SupabaseStorage,
  createFileStorage,
  keyFromUploadUrl,
  safeImageExtension,
  saveUpload,
  setFileStorage,
} from './file-storage';
import { uploadsRouter } from './uploads.routes';
import { tenancyRouter } from '@modules/tenancies/tenancy.routes';

let root: string;

beforeAll(async () => {
  root = await fs.mkdtemp(path.join(os.tmpdir(), 'dormly-storage-'));
});

afterAll(async () => {
  setFileStorage(null);
  await fs.rm(root, { recursive: true, force: true });
});

describe('LocalDiskStorage', () => {
  it('stores, reads and removes files by key', async () => {
    const storage = new LocalDiskStorage(root);
    await storage.put('avatars/u1.png', Buffer.from('png-bytes'), 'image/png');
    expect(await storage.get('avatars/u1.png')).toEqual({
      body: Buffer.from('png-bytes'),
      contentType: 'image/png',
    });
    await storage.remove('avatars/u1.png');
    expect(await storage.get('avatars/u1.png')).toBeNull();
    await expect(storage.remove('avatars/u1.png')).resolves.toBeUndefined();
  });

  it('rejects keys that could escape the upload folder', async () => {
    const storage = new LocalDiskStorage(root);
    for (const key of ['../secret.txt', 'avatars/../../x', '/etc/passwd', 'avatars/a/b.jpg', 'avatars/']) {
      await expect(storage.put(key, Buffer.from('x'), 'image/jpeg')).rejects.toThrow(
        'Invalid storage key.',
      );
    }
  });
});

describe('upload URL helpers', () => {
  it('maps stored /uploads URLs back to keys and ignores anything else', () => {
    expect(keyFromUploadUrl('/uploads/tenant-documents/a-doc-1.jpg')).toBe(
      'tenant-documents/a-doc-1.jpg',
    );
    expect(keyFromUploadUrl('/uploads/tenant-documents/../x.jpg')).toBeNull();
    expect(keyFromUploadUrl('https://example.com/x.jpg')).toBeNull();
    expect(keyFromUploadUrl(null)).toBeNull();
  });

  it('keeps only simple image extensions', () => {
    expect(safeImageExtension('Card.PNG')).toBe('.png');
    expect(safeImageExtension('scan')).toBe('.jpg');
    expect(safeImageExtension('x.j p g')).toBe('.jpg');
    expect(safeImageExtension(undefined)).toBe('.jpg');
  });
});

describe('createFileStorage', () => {
  it('defaults to local disk', () => {
    expect(createFileStorage({}, root).kind).toBe('local');
    expect(createFileStorage({ FILE_STORAGE_DRIVER: 'local' }, root).kind).toBe('local');
  });

  it('requires Supabase credentials for the supabase driver', () => {
    expect(() => createFileStorage({ FILE_STORAGE_DRIVER: 'supabase' }, root)).toThrow(
      'FILE_STORAGE_DRIVER=supabase requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.',
    );
    const storage = createFileStorage(
      {
        FILE_STORAGE_DRIVER: 'Supabase',
        SUPABASE_URL: 'https://example.supabase.co',
        SUPABASE_SERVICE_ROLE_KEY: 'service-key',
      },
      root,
    );
    expect(storage.kind).toBe('supabase');
  });

  it('rejects unknown drivers', () => {
    expect(() => createFileStorage({ FILE_STORAGE_DRIVER: 's3' }, root)).toThrow(
      'Unknown FILE_STORAGE_DRIVER "s3"',
    );
  });
});

describe('SupabaseStorage', () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const responses: Response[] = [];
  const fetchImpl = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return responses.shift() ?? new Response(null, { status: 200 });
  }) as unknown as typeof fetch;
  const storage = new SupabaseStorage({
    url: 'https://example.supabase.co/',
    serviceRoleKey: 'service-key',
    bucket: 'dormly-uploads',
    fetchImpl,
  });

  afterEach(() => {
    calls.length = 0;
    responses.length = 0;
  });

  it('uploads with upsert to the bucket using the service key', async () => {
    await storage.put('tenant-documents/t-doc-1.jpg', Buffer.from('jpg'), 'image/jpeg');
    expect(calls[0].url).toBe(
      'https://example.supabase.co/storage/v1/object/dormly-uploads/tenant-documents/t-doc-1.jpg',
    );
    expect(calls[0].init.method).toBe('POST');
    expect(calls[0].init.headers).toMatchObject({
      Authorization: 'Bearer service-key',
      'Content-Type': 'image/jpeg',
      'x-upsert': 'true',
    });
  });

  it('downloads through the authenticated (private) path', async () => {
    responses.push(
      new Response(Buffer.from('jpg'), { status: 200, headers: { 'content-type': 'image/jpeg' } }),
    );
    const file = await storage.get('tenant-documents/t-doc-1.jpg');
    expect(calls[0].url).toBe(
      'https://example.supabase.co/storage/v1/object/authenticated/dormly-uploads/tenant-documents/t-doc-1.jpg',
    );
    expect(file).toEqual({ body: Buffer.from('jpg'), contentType: 'image/jpeg' });
  });

  it('treats missing objects as null and other failures as errors without leaking the key', async () => {
    responses.push(new Response('{"error":"Object not found"}', { status: 400 }));
    expect(await storage.get('avatars/x.jpg')).toBeNull();

    responses.push(new Response('boom', { status: 500 }));
    const failure = storage.put('avatars/x.jpg', Buffer.from('x'), 'image/jpeg');
    await expect(failure).rejects.toThrow('File storage upload failed (HTTP 500).');
    await expect(failure).rejects.not.toThrow('service-key');
  });
});

async function listen(app: express.Express): Promise<{ server: Server; baseUrl: string }> {
  const server = await new Promise<Server>((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  return { server, baseUrl: `http://127.0.0.1:${(server.address() as AddressInfo).port}` };
}

describe('/uploads route', () => {
  let server: Server;
  let baseUrl: string;

  beforeAll(async () => {
    setFileStorage(new LocalDiskStorage(root));
    await saveUpload('complaints', 'c1.jpg', { buffer: Buffer.from('photo'), mimetype: 'image/jpeg' });
    await saveUpload('tenant-documents', `${TENANCY_A}-doc-1.jpg`, {
      buffer: Buffer.from('aadhaar-a'),
      mimetype: 'image/jpeg',
    });
    const app = express();
    app.use('/uploads', uploadsRouter);
    ({ server, baseUrl } = await listen(app));
  });

  afterAll(() => server.close());

  it('serves public uploads from storage', async () => {
    const res = await fetch(`${baseUrl}/uploads/complaints/c1.jpg`);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('image/jpeg');
    expect(Buffer.from(await res.arrayBuffer()).toString()).toBe('photo');
  });

  it('never serves ID documents publicly, even when the file exists', async () => {
    const res = await fetch(`${baseUrl}/uploads/tenant-documents/${TENANCY_A}-doc-1.jpg`);
    expect(res.status).toBe(404);
  });

  it('answers 404 for missing files and odd paths', async () => {
    expect((await fetch(`${baseUrl}/uploads/complaints/nope.jpg`)).status).toBe(404);
    expect((await fetch(`${baseUrl}/uploads/complaints/..%2F..%2Fpackage.json`)).status).toBe(404);
  });
});

describe('document file endpoint', () => {
  let server: Server;
  let baseUrl: string;

  beforeAll(async () => {
    setFileStorage(new LocalDiskStorage(root));
    await saveUpload('tenant-documents', `${TENANCY_A}-doc-1.jpg`, {
      buffer: Buffer.from('aadhaar-a'),
      mimetype: 'image/jpeg',
    });
    const app = express();
    // Stands in for authGuard + requirePropertyAccess, which have their own tests.
    app.use((req, _res, next) => {
      (req as any).ctxRole = req.header('x-role');
      next();
    });
    app.use('/v1/properties/:propertyId/tenancies', tenancyRouter);
    ({ server, baseUrl } = await listen(app));
  });

  afterAll(() => server.close());

  const fileUrl = (property: string, tenancy: string, doc: string) =>
    `${baseUrl}/v1/properties/${property}/tenancies/${tenancy}/documents/${doc}/file`;

  it('streams the card to owner, admin, manager and staff without caching', async () => {
    for (const role of ['owner', 'admin', 'manager', 'staff']) {
      const res = await fetch(fileUrl(PROPERTY_A, TENANCY_A, DOC_A), { headers: { 'x-role': role } });
      expect(res.status).toBe(200);
      expect(res.headers.get('cache-control')).toBe('private, no-store');
      expect(Buffer.from(await res.arrayBuffer()).toString()).toBe('aadhaar-a');
    }
  });

  it('refuses tenant contexts', async () => {
    const res = await fetch(fileUrl(PROPERTY_A, TENANCY_A, DOC_A), { headers: { 'x-role': 'tenant' } });
    expect(res.status).toBe(403);
  });

  it("does not reach another tenancy's or property's document", async () => {
    const headers = { 'x-role': 'owner' };
    expect((await fetch(fileUrl(PROPERTY_A, TENANCY_A, DOC_B), { headers })).status).toBe(404);
    expect((await fetch(fileUrl(PROPERTY_A, TENANCY_B, DOC_B), { headers })).status).toBe(404);
    expect((await fetch(fileUrl(PROPERTY_A, TENANCY_A, 'not-a-uuid'), { headers })).status).toBe(404);
  });

  it('answers 404 when the stored file is gone', async () => {
    await fs.rm(path.join(root, 'tenant-documents', `${TENANCY_A}-doc-1.jpg`));
    const res = await fetch(fileUrl(PROPERTY_A, TENANCY_A, DOC_A), { headers: { 'x-role': 'owner' } });
    expect(res.status).toBe(404);
  });
});
