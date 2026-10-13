// shared/storage/file-storage.ts
import fs from 'fs/promises';
import path from 'path';

/**
 * Uploaded files live under keys like `tenant-documents/<file>.jpg`; the
 * database keeps `/uploads/<key>` so rows written before this module still work.
 */
export interface StoredFile {
  body: Buffer;
  contentType: string;
}

export interface FileStorage {
  readonly kind: 'local' | 'supabase';
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  /** null when the file does not exist. */
  get(key: string): Promise<StoredFile | null>;
  /** No-op when the file does not exist. */
  remove(key: string): Promise<void>;
}

/** Folders only reachable through authenticated endpoints, never /uploads. */
export const PRIVATE_UPLOAD_FOLDERS: ReadonlySet<string> = new Set(['tenant-documents']);

const KEY_RE = /^[a-z0-9-]+\/[A-Za-z0-9][A-Za-z0-9._-]*$/;

export function assertValidKey(key: string): void {
  if (!KEY_RE.test(key) || key.includes('..')) {
    throw new Error('Invalid storage key.');
  }
}

export function uploadUrlForKey(key: string): string {
  return `/uploads/${key}`;
}

/** Storage key for a stored `/uploads/<key>` URL, or null if it is not one. */
export function keyFromUploadUrl(url: string | null | undefined): string | null {
  if (!url || !url.startsWith('/uploads/')) return null;
  const key = url.slice('/uploads/'.length);
  return KEY_RE.test(key) && !key.includes('..') ? key : null;
}

const CONTENT_TYPES: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
};

export function contentTypeForKey(key: string): string {
  return CONTENT_TYPES[path.extname(key).toLowerCase()] ?? 'application/octet-stream';
}

export class LocalDiskStorage implements FileStorage {
  readonly kind = 'local' as const;

  constructor(private readonly rootDir: string) {}

  private pathFor(key: string): string {
    assertValidKey(key);
    return path.join(this.rootDir, ...key.split('/'));
  }

  async put(key: string, body: Buffer, _contentType: string): Promise<void> {
    const target = this.pathFor(key);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, body);
  }

  async get(key: string): Promise<StoredFile | null> {
    try {
      const body = await fs.readFile(this.pathFor(key));
      return { body, contentType: contentTypeForKey(key) };
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw err;
    }
  }

  async remove(key: string): Promise<void> {
    try {
      await fs.unlink(this.pathFor(key));
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') throw err;
    }
  }
}

type FetchLike = typeof fetch;

export interface SupabaseStorageOptions {
  url: string;
  serviceRoleKey: string;
  bucket: string;
  fetchImpl?: FetchLike;
}

/** Supabase Storage over its REST API. The bucket must be private. */
export class SupabaseStorage implements FileStorage {
  readonly kind = 'supabase' as const;
  private readonly base: string;
  private readonly fetchImpl: FetchLike;

  constructor(private readonly opts: SupabaseStorageOptions) {
    this.base = `${opts.url.replace(/\/+$/, '')}/storage/v1/object`;
    this.fetchImpl = opts.fetchImpl ?? fetch;
  }

  private objectUrl(prefix: string, key: string): string {
    assertValidKey(key);
    const encoded = key.split('/').map(encodeURIComponent).join('/');
    return `${this.base}${prefix}/${encodeURIComponent(this.opts.bucket)}/${encoded}`;
  }

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return {
      Authorization: `Bearer ${this.opts.serviceRoleKey}`,
      apikey: this.opts.serviceRoleKey,
      ...extra,
    };
  }

  async put(key: string, body: Buffer, contentType: string): Promise<void> {
    const res = await this.fetchImpl(this.objectUrl('', key), {
      method: 'POST',
      headers: this.headers({ 'Content-Type': contentType, 'x-upsert': 'true' }),
      body: new Uint8Array(body),
    });
    if (!res.ok) {
      throw new Error(`File storage upload failed (HTTP ${res.status}).`);
    }
  }

  async get(key: string): Promise<StoredFile | null> {
    const res = await this.fetchImpl(this.objectUrl('/authenticated', key), {
      method: 'GET',
      headers: this.headers(),
    });
    // Supabase answers 400 with "Object not found" for missing objects.
    if (res.status === 404 || res.status === 400) return null;
    if (!res.ok) {
      throw new Error(`File storage download failed (HTTP ${res.status}).`);
    }
    const body = Buffer.from(await res.arrayBuffer());
    return { body, contentType: res.headers.get('content-type') ?? contentTypeForKey(key) };
  }

  async remove(key: string): Promise<void> {
    const res = await this.fetchImpl(this.objectUrl('', key), {
      method: 'DELETE',
      headers: this.headers(),
    });
    if (!res.ok && res.status !== 404 && res.status !== 400) {
      throw new Error(`File storage delete failed (HTTP ${res.status}).`);
    }
  }
}

export const LOCAL_UPLOAD_ROOT = path.join(__dirname, '../../../uploads');

export type StorageEnv = Record<string, string | undefined>;

/**
 * FILE_STORAGE_DRIVER=supabase needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
 * (SUPABASE_STORAGE_BUCKET defaults to dormly-uploads). Anything else keeps
 * files on local disk, which Render wipes on every deploy or restart.
 */
export function createFileStorage(
  source: StorageEnv = process.env,
  localRoot: string = LOCAL_UPLOAD_ROOT,
): FileStorage {
  const driver = (source.FILE_STORAGE_DRIVER ?? 'local').trim().toLowerCase();
  if (driver === 'supabase') {
    const url = source.SUPABASE_URL?.trim();
    const serviceRoleKey = source.SUPABASE_SERVICE_ROLE_KEY?.trim();
    if (!url || !serviceRoleKey) {
      throw new Error(
        'FILE_STORAGE_DRIVER=supabase requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.',
      );
    }
    const bucket = source.SUPABASE_STORAGE_BUCKET?.trim() || 'dormly-uploads';
    return new SupabaseStorage({ url, serviceRoleKey, bucket });
  }
  if (driver !== 'local') {
    throw new Error(`Unknown FILE_STORAGE_DRIVER "${driver}" (use "local" or "supabase").`);
  }
  return new LocalDiskStorage(localRoot);
}

let current: FileStorage | null = null;

export function fileStorage(): FileStorage {
  current ??= createFileStorage();
  return current;
}

export function setFileStorage(storage: FileStorage | null): void {
  current = storage;
}

/** Reads a key from the active storage, falling back to local disk for files saved before the switch. */
export async function readUpload(key: string): Promise<StoredFile | null> {
  const storage = fileStorage();
  const found = await storage.get(key);
  if (found || storage.kind === 'local') return found;
  return new LocalDiskStorage(LOCAL_UPLOAD_ROOT).get(key);
}

/** Lower-case extension of an uploaded image name, `.jpg` when missing or odd. */
export function safeImageExtension(originalName: string | undefined): string {
  const ext = path.extname(originalName ?? '').toLowerCase();
  return /^\.[a-z0-9]{1,5}$/.test(ext) ? ext : '.jpg';
}

/** Best-effort cleanup for an upload whose request was rejected. */
export async function discardUpload(url: string | null | undefined): Promise<void> {
  const key = keyFromUploadUrl(url);
  if (!key) return;
  try {
    await fileStorage().remove(key);
  } catch {
    // An orphaned image is harmless; the request already failed for its own reason.
  }
}

/** Saves a multer memory upload and returns the `/uploads/<key>` URL to store. */
export async function saveUpload(
  folder: string,
  filename: string,
  file: { buffer: Buffer; mimetype: string },
): Promise<string> {
  const key = `${folder}/${filename}`;
  const byExtension = contentTypeForKey(key);
  const contentType =
    byExtension === 'application/octet-stream' ? file.mimetype : byExtension;
  await fileStorage().put(key, file.buffer, contentType);
  return uploadUrlForKey(key);
}
