import { describe, expect, it } from 'vitest';
import type { Response } from 'express';
import type { AuthedRequest } from './auth-guard';
import { userRateLimit } from './rate-limit';

function harness(options: { capacity: number; refillPerSecond: number; sweepAbove?: number }) {
  let clock = 1_000_000;
  const limiter = userRateLimit({
    ...options,
    code: 'test_rate_limited',
    message: 'Slow down.',
    now: () => clock,
  });
  const call = (userId: string | undefined) => {
    const res = {
      statusCode: 200,
      headers: {} as Record<string, string>,
      body: undefined as unknown,
      set(name: string, value: string) {
        this.headers[name] = value;
        return this;
      },
      status(code: number) {
        this.statusCode = code;
        return this;
      },
      json(body: unknown) {
        this.body = body;
        return this;
      },
    };
    let passed = false;
    limiter({ userId } as AuthedRequest, res as unknown as Response, () => {
      passed = true;
    });
    return { passed, status: passed ? 200 : res.statusCode, retryAfter: res.headers['Retry-After'], body: res.body };
  };
  return { limiter, call, advance: (ms: number) => (clock += ms) };
}

describe('userRateLimit', () => {
  it('allows a burst up to capacity, then refuses with 429 and Retry-After', () => {
    const { call } = harness({ capacity: 3, refillPerSecond: 0.5 });
    expect([call('u1'), call('u1'), call('u1')].every((r) => r.passed)).toBe(true);
    const refused = call('u1');
    expect(refused.status).toBe(429);
    expect(refused.retryAfter).toBe('2');
    expect(refused.body).toEqual({ error: 'Slow down.', code: 'test_rate_limited' });
  });

  it('refills over time without exceeding capacity', () => {
    const { call, advance } = harness({ capacity: 2, refillPerSecond: 0.5 });
    call('u1');
    call('u1');
    expect(call('u1').status).toBe(429);
    advance(1999);
    expect(call('u1').status).toBe(429);
    advance(1);
    expect(call('u1').passed).toBe(true);
    advance(60_000);
    expect(call('u1').passed).toBe(true);
    expect(call('u1').passed).toBe(true);
    expect(call('u1').status).toBe(429);
  });

  it('keeps an independent budget for each user', () => {
    const { call } = harness({ capacity: 1, refillPerSecond: 0.1 });
    expect(call('u1').passed).toBe(true);
    expect(call('u1').status).toBe(429);
    expect(call('u2').passed).toBe(true);
    expect(call('u2').status).toBe(429);
  });

  it('refuses requests without an authenticated user and keeps no state for them', () => {
    const { limiter, call } = harness({ capacity: 5, refillPerSecond: 1 });
    const res = call(undefined);
    expect(res.status).toBe(401);
    expect(call('').status).toBe(401);
    expect(limiter.size).toBe(0);
  });

  it('drops idle buckets once the map is large', () => {
    const { limiter, call, advance } = harness({ capacity: 2, refillPerSecond: 1, sweepAbove: 3 });
    call('a');
    call('b');
    call('c');
    expect(limiter.size).toBe(3);
    advance(2000);
    call('d');
    expect(limiter.size).toBe(1);
  });
});
