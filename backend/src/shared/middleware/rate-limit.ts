// shared/middleware/rate-limit.ts
//
// Token-bucket rate limit keyed by the authenticated user id, so users behind
// one network address do not share a budget. Mount after authGuard.
//
// Buckets live in this Node process only: each instance (and each restart)
// keeps its own counts, so N instances allow up to N times the limit. A shared
// limit would need Redis or a database table.

import type { NextFunction, Response } from 'express';
import type { AuthedRequest } from './auth-guard';

export interface UserRateLimitOptions {
  /** Requests a user may make in one burst. */
  capacity: number;
  /** Requests regained per second, up to [capacity]. */
  refillPerSecond: number;
  code: string;
  message: string;
  now?: () => number;
  /** Idle buckets are dropped once this many are held. */
  sweepAbove?: number;
}

export interface UserRateLimiter {
  (req: AuthedRequest, res: Response, next: NextFunction): void;
  reset(): void;
  readonly size: number;
}

export function userRateLimit(options: UserRateLimitOptions): UserRateLimiter {
  const { capacity, refillPerSecond, code, message } = options;
  const now = options.now ?? (() => Date.now());
  const sweepAbove = options.sweepAbove ?? 10_000;
  const refillMs = (capacity / refillPerSecond) * 1000;
  const buckets = new Map<string, { tokens: number; updatedAt: number }>();

  const sweep = (t: number) => {
    for (const [key, bucket] of buckets) {
      if (t - bucket.updatedAt >= refillMs) buckets.delete(key);
    }
  };

  const limiter = ((req: AuthedRequest, res: Response, next: NextFunction) => {
    const userId = typeof req.userId === 'string' && req.userId ? req.userId : null;
    if (!userId) {
      res.status(401).json({ error: 'Invalid or expired token' });
      return;
    }
    const t = now();
    let bucket = buckets.get(userId);
    if (!bucket) {
      if (buckets.size >= sweepAbove) sweep(t);
      bucket = { tokens: capacity, updatedAt: t };
      buckets.set(userId, bucket);
    } else {
      const elapsed = Math.max(0, t - bucket.updatedAt);
      bucket.tokens = Math.min(capacity, bucket.tokens + (elapsed / 1000) * refillPerSecond);
      bucket.updatedAt = t;
    }
    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      next();
      return;
    }
    const retryAfter = Math.max(1, Math.ceil((1 - bucket.tokens) / refillPerSecond));
    res.set('Retry-After', String(retryAfter));
    res.status(429).json({ error: message, code });
  }) as UserRateLimiter;

  limiter.reset = () => buckets.clear();
  Object.defineProperty(limiter, 'size', { get: () => buckets.size });
  return limiter;
}
