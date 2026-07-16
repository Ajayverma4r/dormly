// modules/auth/auth.service.ts
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { query } from '@config/db';
import { env } from '@config/env';

function hashOtp(code: string): string {
  return crypto.createHash('sha256').update(code).digest('hex');
}

function generateOtp(): string {
  return String(crypto.randomInt(100000, 999999));
}

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
  ): Promise<{ accessToken: string; refreshToken: string; userId: string; organizationId?: string }> {
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
      // Even in bypass mode, require a 6-digit shape so the UI flow still makes sense.
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
    } else {
      // Existing users don't necessarily have an organization — a tenant-only
      // phone number never gets one. Only owners/admins do.
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

    return { accessToken, refreshToken, userId: user.id, organizationId };
  }

  async refresh(refreshToken: string): Promise<{ accessToken: string }> {
    const payload = jwt.verify(refreshToken, env.jwtRefreshSecret) as { sub: string };
    const accessToken = jwt.sign({ sub: payload.sub }, env.jwtAccessSecret, {
      expiresIn: env.jwtAccessTtl,
    } as jwt.SignOptions);
    return { accessToken };
  }
}