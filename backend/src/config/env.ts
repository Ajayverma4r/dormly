// config/env.ts
import 'dotenv/config';

function required(key: string): string {
  const value = process.env[key];
  if (!value) throw new Error(`Missing required env var: ${key}`);
  return value;
}

export const env = {
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: Number(process.env.PORT ?? 4000),
  databaseUrl: required('DATABASE_URL'),
  jwtAccessSecret: required('JWT_ACCESS_SECRET'),
  jwtRefreshSecret: required('JWT_REFRESH_SECRET'),
  jwtAccessTtl: process.env.JWT_ACCESS_TTL ?? '15m',
  jwtRefreshTtl: process.env.JWT_REFRESH_TTL ?? '30d',
  otpTtlSeconds: Number(process.env.OTP_TTL_SECONDS ?? 300),
  otpBypass: process.env.OTP_BYPASS === 'true',
  // Razorpay — obtain from https://dashboard.razorpay.com/app/keys
  razorpayKeyId: required('RAZORPAY_KEY_ID'),
  razorpayKeySecret: required('RAZORPAY_KEY_SECRET'),
  // Set in Razorpay Dashboard → Webhooks → Secret
  razorpayWebhookSecret: required('RAZORPAY_WEBHOOK_SECRET'),
  // Grace period (days) granted after a payment failure before downgrading to free
  subscriptionGracePeriodDays: Number(process.env.SUBSCRIPTION_GRACE_PERIOD_DAYS ?? 3),

  /**
   * Test payment bypass / mock checkout.
   * Enabled when any of:
   *   - OTP_BYPASS=true
   *   - ALLOW_TEST_ACTIVATE=true
   *   - Razorpay key is test (rzp_test_…) or placeholder
   * Auto-disables once you switch to live rzp_live_ keys (unless OTP_BYPASS stays on).
   */
  get allowTestActivate(): boolean {
    const key = process.env.RAZORPAY_KEY_ID ?? '';
    return (
      process.env.OTP_BYPASS === 'true' ||
      process.env.ALLOW_TEST_ACTIVATE === 'true' ||
      key.startsWith('rzp_test_') ||
      key.includes('placeholder')
    );
  },
};