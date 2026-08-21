// modules/auth/auth.service.ts
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { query } from '@config/db';
import { env } from '@config/env';
import { SubscriptionService } from '../subscriptions/subscription.service';

function hashOtp(code: string): string {
  return crypto.createHash('sha256').update(code).digest('hex');
}

function generateOtp(): string {
  return String(crypto.randomInt(100000, 999999));
}

export type UserProfile = {
  id: string;
  phone: string;
  name: string | null;
  email: string | null;
  avatarUrl: string | null;
  profileComplete: boolean;
  propertyCount: number;
  organizationId: string | null;
  planSlug: string | null;
  planName: string | null;
  subscriptionStatus: string | null;
};

export class AuthService {
  async requestOtp(phone: string): Promise<void> {
    const code = generateOtp();
    const codeHash = hashOtp(code);
    const expiresAt = new Date(Date.now() + env.otpTtlSeconds * 1000);

    await query(
      `INSERT INTO otp_codes (phone, code_hash, expires_at) VALUES ($1, $2, $3)`,
      [phone, codeHash, expiresAt],
    );

    // eslint-disable-next-line no-console
    console.log(`[OTP] ${phone} -> ${code} (expires in ${env.otpTtlSeconds}s)`);
    if (env.otpBypass) {
      // eslint-disable-next-line no-console
      console.log(`[OTP] DEV MODE: any 6-digit code will be accepted for ${phone}`);
    }
  }

  async verifyOtp(
    phone: string,
    code: string,
  ): Promise<{
    accessToken: string;
    refreshToken: string;
    userId: string;
    organizationId?: string;
    user: UserProfile;
  }> {
    if (!env.otpBypass) {
      const codeHash = hashOtp(code);
      const rows = await query<{ id: string }>(
        `SELECT id FROM otp_codes
         WHERE phone = $1 AND code_hash = $2 AND consumed_at IS NULL AND expires_at > now()
         ORDER BY created_at DESC LIMIT 1`,
        [phone, codeHash],
      );
      if (!rows[0]) {
        throw new Error('Invalid or expired OTP');
      }
      await query(`UPDATE otp_codes SET consumed_at = now() WHERE id = $1`, [rows[0].id]);
    } else if (!/^\d{6}$/.test(code)) {
      throw new Error('Enter any 6-digit code');
    }

    let user = (await query<{ id: string }>(`SELECT id FROM users WHERE phone = $1`, [phone]))[0];
    let organizationId: string | undefined;

    if (!user) {
      user = (await query<{ id: string }>(
        `INSERT INTO users (phone) VALUES ($1) RETURNING id`,
        [phone],
      ))[0];

      const org = (await query<{ id: string }>(
        `INSERT INTO organizations (name, owner_user_id) VALUES ($1, $2) RETURNING id`,
        [`${phone}'s Organization`, user.id],
      ))[0];
      organizationId = org.id;

      await query(
        `INSERT INTO memberships (user_id, organization_id, role) VALUES ($1, $2, 'owner')`,
        [user.id, organizationId],
      );

      try {
        await new SubscriptionService().createTrialSubscription(
          organizationId,
          user.id,
        );
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error('[auth] createTrialSubscription failed:', err);
      }
    } else {
      const membership = (await query<{ organization_id: string }>(
        `SELECT organization_id FROM memberships WHERE user_id = $1 ORDER BY created_at LIMIT 1`,
        [user.id],
      ))[0];
      organizationId = membership?.organization_id;
    }

    const accessToken = jwt.sign({ sub: user.id }, env.jwtAccessSecret, {
      expiresIn: env.jwtAccessTtl,
    } as jwt.SignOptions);
    const refreshToken = jwt.sign({ sub: user.id, type: 'refresh' }, env.jwtRefreshSecret, {
      expiresIn: env.jwtRefreshTtl,
    } as jwt.SignOptions);

    const profile = await this.getProfile(user.id);

    return {
      accessToken,
      refreshToken,
      userId: user.id,
      organizationId,
      user: profile,
    };
  }

  async refresh(refreshToken: string): Promise<{ accessToken: string }> {
    const payload = jwt.verify(refreshToken, env.jwtRefreshSecret) as { sub: string };
    const accessToken = jwt.sign({ sub: payload.sub }, env.jwtAccessSecret, {
      expiresIn: env.jwtAccessTtl,
    } as jwt.SignOptions);
    return { accessToken };
  }

  async getProfile(userId: string): Promise<UserProfile> {
    // email / avatar_url require migration 012 — fall back gracefully if missing.
    let u: {
      id: string;
      phone: string;
      name: string | null;
      email: string | null;
      avatar_url: string | null;
    };

    try {
      const rows = await query<{
        id: string;
        phone: string;
        name: string | null;
        email: string | null;
        avatar_url: string | null;
      }>(
        `SELECT id, phone, name, email, avatar_url FROM users WHERE id = $1`,
        [userId],
      );
      if (!rows[0]) throw new Error('User not found');
      u = rows[0];
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      if (!msg.includes('email') && !msg.includes('avatar_url') && !msg.includes('column')) {
        throw err;
      }
      const rows = await query<{ id: string; phone: string; name: string | null }>(
        `SELECT id, phone, name FROM users WHERE id = $1`,
        [userId],
      );
      if (!rows[0]) throw new Error('User not found');
      u = { ...rows[0], email: null, avatar_url: null };
    }

    const membership = (await query<{ organization_id: string }>(
      `SELECT organization_id FROM memberships
       WHERE  user_id = $1 AND role IN ('owner', 'admin')
       ORDER BY created_at LIMIT 1`,
      [userId],
    ))[0];

    let propertyCount = 0;
    let planSlug: string | null = null;
    let planName: string | null = null;
    let subscriptionStatus: string | null = null;

    if (membership?.organization_id) {
      const countRows = await query<{ count: string }>(
        `SELECT COUNT(*)::text AS count FROM properties WHERE organization_id = $1`,
        [membership.organization_id],
      );
      propertyCount = Number(countRows[0]?.count ?? 0);

      try {
        const sub = await new SubscriptionService().getOrgSubscription(
          membership.organization_id,
        );
        if (sub) {
          planSlug = (sub.plan_slug as string) ?? null;
          planName = (sub.plan_name as string) ?? null;
          subscriptionStatus = (sub.status as string) ?? null;
        }
      } catch {
        // ignore — subscription optional for profile read
      }
    }

    const name = u.name?.trim() ? u.name.trim() : null;

    return {
      id: u.id,
      phone: u.phone,
      name,
      email: u.email,
      avatarUrl: u.avatar_url,
      profileComplete: Boolean(name),
      propertyCount,
      organizationId: membership?.organization_id ?? null,
      planSlug,
      planName,
      subscriptionStatus,
    };
  }

  async updateProfile(
    userId: string,
    input: { name?: string; email?: string | null; avatarUrl?: string | null },
  ): Promise<UserProfile> {
    const name = input.name?.trim();
    if (input.name !== undefined && (!name || name.length < 2)) {
      throw new Error('Full name is required (at least 2 characters).');
    }

    const email =
      input.email === undefined
        ? undefined
        : input.email?.trim()
          ? input.email.trim()
          : null;

    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new Error('Enter a valid email address.');
    }

    try {
      await query(
        `UPDATE users
         SET name       = COALESCE($2, name),
             email      = CASE WHEN $3::boolean THEN $4 ELSE email END,
             avatar_url = CASE WHEN $5::boolean THEN $6 ELSE avatar_url END,
             updated_at = now()
         WHERE id = $1`,
        [
          userId,
          name ?? null,
          input.email !== undefined,
          email ?? null,
          input.avatarUrl !== undefined,
          input.avatarUrl ?? null,
        ],
      );
    } catch (err) {
      // Migration 012 not applied — update name only.
      if (name) {
        await query(
          `UPDATE users SET name = $2, updated_at = now() WHERE id = $1`,
          [userId, name],
        );
      } else {
        throw err;
      }
    }

    return this.getProfile(userId);
  }
}
