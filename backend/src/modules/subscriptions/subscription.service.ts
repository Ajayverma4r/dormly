// modules/subscriptions/subscription.service.ts
//
// Owns the full subscription lifecycle:
//   - Trial provisioning on org signup
//   - Razorpay order creation
//   - Webhook event processing (with idempotency)
//   - Graceful downgrade of expired subscriptions (called by the background job)
//   - Cancel-at-period-end

import crypto from 'crypto';
import Razorpay from 'razorpay';
import { query, pool } from '@config/db';
import { env } from '@config/env';

// ---------------------------------------------------------------------------
// Razorpay client (lazy singleton — not instantiated until first use so that
// missing env vars during tests don't blow up on import)
// ---------------------------------------------------------------------------
let _razorpay: Razorpay | null = null;
function getRazorpay(): Razorpay {
  if (!_razorpay) {
    _razorpay = new Razorpay({
      key_id: env.razorpayKeyId,
      key_secret: env.razorpayKeySecret,
    });
  }
  return _razorpay;
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
export interface RazorpayOrderResult {
  orderId: string;
  amount: number;      // in ₹ (human-readable)
  amountPaise: number; // for passing directly to Razorpay JS SDK
  currency: string;
  keyId: string;       // frontend needs this to open the checkout
  /** When true, Flutter should skip Razorpay SDK and call test-activate. */
  testMode?: boolean;
}

interface PaymentRow {
  id: string;
  subscription_id: string;
  organization_id: string;
  status: string;
  metadata: Record<string, string> | string;
  billing_period_start: Date;
  billing_period_end: Date;
}

interface SubRow {
  id: string;
  plan_id: string;
  status: string;
}

// ---------------------------------------------------------------------------
// SubscriptionService
// ---------------------------------------------------------------------------
export class SubscriptionService {
  // ---- Provisioning -------------------------------------------------------

  /**
   * Auto-called when a new organization is created.
   * Creates a 14-day Pro Trial subscription row and writes the first
   * history event. Idempotent — silently no-ops if the org already has a row.
   */
  async createTrialSubscription(
    organizationId: string,
    createdByUserId: string,
  ): Promise<void> {
    const plans = await query<{ id: string; slug: string; trial_days: number }>(
      `SELECT id, slug, trial_days FROM plans WHERE slug = 'pro_trial' AND is_active = true`,
    );
    const proTrial = plans[0];
    if (!proTrial) throw new Error("'pro_trial' plan is missing from the database.");

    const trialEndsAt = new Date(
      Date.now() + proTrial.trial_days * 24 * 60 * 60 * 1000,
    );

    const inserted = await query<{ id: string }>(
      `INSERT INTO subscriptions
         (organization_id, plan_id, status, trial_ends_at,
          current_period_start, current_period_end)
       VALUES ($1, $2, 'trialing', $3, now(), $3)
       ON CONFLICT (organization_id) DO NOTHING
       RETURNING id`,
      [organizationId, proTrial.id, trialEndsAt],
    );

    if (!inserted.length) return; // already existed — skip history write

    await query(
      `INSERT INTO subscription_history
         (organization_id, subscription_id, to_plan_id, to_status, reason, changed_by_user_id)
       VALUES ($1, $2, $3, 'trialing', 'trial_started', $4)`,
      [organizationId, inserted[0].id, proTrial.id, createdByUserId],
    );
  }

  // ---- Read ---------------------------------------------------------------

  async getOrgSubscription(organizationId: string) {
    const rows = await query(
      `SELECT s.*,
              p.slug            AS plan_slug,
              p.display_name    AS plan_name,
              p.price_inr_monthly,
              p.price_inr_yearly
       FROM   subscriptions s
       JOIN   plans          p ON p.id = s.plan_id
       WHERE  s.organization_id = $1`,
      [organizationId],
    );
    return rows[0] ?? null;
  }

  async getSubscriptionHistory(organizationId: string) {
    return query(
      `SELECT h.*,
              fp.slug AS from_plan_slug,
              tp.slug AS to_plan_slug
       FROM   subscription_history h
       LEFT   JOIN plans fp ON fp.id = h.from_plan_id
       JOIN   plans       tp ON tp.id = h.to_plan_id
       WHERE  h.organization_id = $1
       ORDER  BY h.created_at DESC
       LIMIT  50`,
      [organizationId],
    );
  }

  // ---- Razorpay: Create Order ---------------------------------------------

  /**
   * Creates a Razorpay order for upgrading/renewing a subscription.
   * Inserts a subscription_payments row with status='created'.
   * The frontend should use the returned orderId + keyId to open checkout.
   */
  async createOrder(
    organizationId: string,
    planSlug: string,
    billingCycle: 'monthly' | 'yearly',
    userId: string,
  ): Promise<RazorpayOrderResult> {
    const plans = await query<{
      id: string;
      slug: string;
      price_inr_monthly: string;
      price_inr_yearly: string;
    }>(
      `SELECT id, slug, price_inr_monthly, price_inr_yearly
       FROM   plans
       WHERE  slug = $1 AND is_active = true`,
      [planSlug],
    );
    const plan = plans[0];
    if (!plan) throw new Error(`Plan '${planSlug}' not found or inactive.`);

    const amountInr =
      billingCycle === 'yearly'
        ? Number(plan.price_inr_yearly)
        : Number(plan.price_inr_monthly);

    if (amountInr <= 0) {
      throw new Error('Cannot create a payment order for a zero-price plan.');
    }

    const sub = await this.getOrgSubscription(organizationId);
    if (!sub) throw new Error('Organization has no subscription record. Create trial first.');

    const periodEnd = new Date();
    if (billingCycle === 'yearly') {
      periodEnd.setFullYear(periodEnd.getFullYear() + 1);
    } else {
      periodEnd.setMonth(periodEnd.getMonth() + 1);
    }

    // Test mode: placeholder Razorpay keys or OTP_BYPASS — skip live Razorpay API.
    const isTestMode =
      env.otpBypass ||
      env.razorpayKeyId.includes('placeholder') ||
      env.razorpayKeySecret.includes('placeholder');

    let orderId: string;
    if (isTestMode) {
      orderId = `order_test_${organizationId.slice(0, 8)}_${Date.now()}`;
    } else {
      const rzpOrder = await getRazorpay().orders.create({
        amount: amountInr * 100,
        currency: 'INR',
        receipt: `dormly_${organizationId.slice(0, 8)}_${Date.now()}`,
        notes: { organizationId, planSlug, billingCycle, userId },
      });
      orderId = rzpOrder.id;
    }

    await query(
      `INSERT INTO subscription_payments
         (subscription_id, organization_id, razorpay_order_id,
          amount_inr, status, billing_period_start, billing_period_end, metadata)
       VALUES ($1, $2, $3, $4, 'created', now(), $5, $6)`,
      [
        sub.id,
        organizationId,
        orderId,
        amountInr,
        periodEnd,
        JSON.stringify({ planSlug, billingCycle, userId, testMode: isTestMode }),
      ],
    );

    return {
      orderId,
      amount: amountInr,
      amountPaise: amountInr * 100,
      currency: 'INR',
      keyId: env.razorpayKeyId,
      testMode: isTestMode,
    };
  }

  // ---- Razorpay: Webhook --------------------------------------------------

  /**
   * Verifies the HMAC-SHA256 signature and dispatches the event.
   * Idempotent — duplicate webhook deliveries for the same payment are no-ops.
   *
   * Signature header: X-Razorpay-Signature
   * Secret:           RAZORPAY_WEBHOOK_SECRET (set in Razorpay Dashboard)
   */
  async handleWebhookEvent(rawBody: Buffer, signature: string): Promise<void> {
    this._verifyWebhookSignature(rawBody, signature);

    const event = JSON.parse(rawBody.toString('utf8')) as {
      event: string;
      payload: Record<string, any>;
    };

    switch (event.event) {
      case 'payment.captured':
        await this._handlePaymentCaptured(event.payload.payment.entity);
        break;
      case 'payment.failed':
        await this._handlePaymentFailed(event.payload.payment.entity);
        break;
      case 'refund.created':
        await this._handleRefund(event.payload.refund.entity);
        break;
      // Razorpay Subscriptions / AutoPay — extend period when a mandate charge succeeds
      case 'subscription.charged':
        await this._handleSubscriptionCharged(event.payload);
        break;
      default:
        // Silently ack unknown events — return 200 so Razorpay stops retrying
        break;
    }
  }

  private _verifyWebhookSignature(rawBody: Buffer, receivedSig: string): void {
    const expected = crypto
      .createHmac('sha256', env.razorpayWebhookSecret)
      .update(rawBody)
      .digest('hex');

    // timingSafeEqual prevents timing-oracle attacks
    if (
      expected.length !== receivedSig.length ||
      !crypto.timingSafeEqual(Buffer.from(expected, 'hex'), Buffer.from(receivedSig, 'hex'))
    ) {
      throw new Error('Invalid Razorpay webhook signature.');
    }
  }

  private async _handlePaymentCaptured(payment: any): Promise<void> {
    const orderId: string = payment.order_id;
    const paymentId: string = payment.id;

    const pmtRows = await query<PaymentRow>(
      `SELECT id, subscription_id, organization_id, status, metadata,
              billing_period_start, billing_period_end
       FROM   subscription_payments
       WHERE  razorpay_order_id = $1`,
      [orderId],
    );
    if (!pmtRows.length) return; // unknown order — not ours
    const pmt = pmtRows[0];
    if (pmt.status === 'paid') return; // idempotency: already processed

    // Mark payment paid
    await query(
      `UPDATE subscription_payments
       SET razorpay_payment_id = $1,
           status              = 'paid',
           payment_method      = $2,
           paid_at             = now(),
           updated_at          = now()
       WHERE razorpay_order_id = $3`,
      [paymentId, payment.method ?? null, orderId],
    );

    const meta =
      typeof pmt.metadata === 'string' ? JSON.parse(pmt.metadata) : pmt.metadata;
    const { planSlug } = meta as { planSlug: string };

    const planRows = await query<{ id: string }>(
      `SELECT id FROM plans WHERE slug = $1`,
      [planSlug],
    );
    if (!planRows.length) return;
    const newPlanId = planRows[0].id;

    const subRows = await query<SubRow>(
      `SELECT id, plan_id, status FROM subscriptions WHERE id = $1`,
      [pmt.subscription_id],
    );
    if (!subRows.length) return;
    const sub = subRows[0];

    // Advance subscription to active
    await query(
      `UPDATE subscriptions
       SET plan_id              = $1,
           status               = 'active',
           current_period_start = $2,
           current_period_end   = $3,
           trial_ends_at        = NULL,
           cancel_at_period_end = false,
           cancelled_at         = NULL,
           grace_period_ends_at = NULL,
           updated_at           = now()
       WHERE id = $4`,
      [newPlanId, pmt.billing_period_start, pmt.billing_period_end, pmt.subscription_id],
    );

    await query(
      `INSERT INTO subscription_history
         (organization_id, subscription_id, from_plan_id, to_plan_id,
          from_status, to_status, reason)
       VALUES ($1, $2, $3, $4, $5, 'active', 'payment_succeeded')`,
      [pmt.organization_id, pmt.subscription_id, sub.plan_id, newPlanId, sub.status],
    );
  }

  /**
   * Razorpay AutoPay / subscription.charged — extend current_period_end and
   * keep the org on Premium. Banner disappears once days_left > 7 again.
   */
  private async _handleSubscriptionCharged(payload: Record<string, any>): Promise<void> {
    const subscriptionEntity = payload.subscription?.entity ?? payload.subscription;
    const paymentEntity = payload.payment?.entity ?? payload.payment;
    if (!subscriptionEntity?.id) return;

    const rzpSubId: string = subscriptionEntity.id;
    const subs = await query<{
      id: string;
      organization_id: string;
      plan_id: string;
      status: string;
      current_period_end: Date;
    }>(
      `SELECT id, organization_id, plan_id, status, current_period_end
       FROM   subscriptions
       WHERE  razorpay_subscription_id = $1`,
      [rzpSubId],
    );
    if (!subs.length) return;
    const sub = subs[0];

    // Prefer period from Razorpay; otherwise +1 month from current end.
    let periodStart = new Date(sub.current_period_end);
    let periodEnd = new Date(sub.current_period_end);
    periodEnd.setMonth(periodEnd.getMonth() + 1);

    const chargeAt = paymentEntity?.created_at
      ? new Date(Number(paymentEntity.created_at) * 1000)
      : null;
    if (subscriptionEntity.current_end) {
      periodEnd = new Date(Number(subscriptionEntity.current_end) * 1000);
    }
    if (subscriptionEntity.current_start) {
      periodStart = new Date(Number(subscriptionEntity.current_start) * 1000);
    } else if (chargeAt) {
      periodStart = chargeAt;
    }

    await query(
      `UPDATE subscriptions
       SET status               = 'active',
           current_period_start = $1,
           current_period_end   = $2,
           auto_renew           = true,
           mandate_active       = true,
           cancel_at_period_end = false,
           cancelled_at         = NULL,
           grace_period_ends_at = NULL,
           trial_ends_at        = NULL,
           updated_at           = now()
       WHERE id = $3`,
      [periodStart, periodEnd, sub.id],
    );

    await query(
      `INSERT INTO subscription_history
         (organization_id, subscription_id, from_plan_id, to_plan_id,
          from_status, to_status, reason, note)
       VALUES ($1, $2, $3, $3, $4, 'active', 'payment_succeeded', $5)`,
      [
        sub.organization_id,
        sub.id,
        sub.plan_id,
        sub.status,
        `auto_renew:${paymentEntity?.id ?? rzpSubId}`,
      ],
    );
  }

  private async _handlePaymentFailed(payment: any): Promise<void> {
    const orderId: string = payment.order_id;

    const pmtRows = await query<PaymentRow & { subscription_id: string; organization_id: string }>(
      `SELECT id, status, subscription_id, organization_id
       FROM   subscription_payments
       WHERE  razorpay_order_id = $1`,
      [orderId],
    );
    if (!pmtRows.length || pmtRows[0].status === 'failed') return; // idempotent
    const pmt = pmtRows[0];

    await query(
      `UPDATE subscription_payments
       SET razorpay_payment_id = $1,
           status              = 'failed',
           failure_code        = $2,
           failure_reason      = $3,
           updated_at          = now()
       WHERE razorpay_order_id = $4`,
      [payment.id, payment.error_code ?? null, payment.error_description ?? null, orderId],
    );

    const subRows = await query<SubRow>(
      `SELECT id, plan_id, status FROM subscriptions WHERE id = $1`,
      [pmt.subscription_id],
    );
    if (!subRows.length || subRows[0].status === 'expired') return;
    const sub = subRows[0];

    const gracePeriodEndsAt = new Date(
      Date.now() + env.subscriptionGracePeriodDays * 24 * 60 * 60 * 1000,
    );

    await query(
      `UPDATE subscriptions
       SET status               = 'past_due',
           grace_period_ends_at = $1,
           updated_at           = now()
       WHERE id = $2`,
      [gracePeriodEndsAt, pmt.subscription_id],
    );

    await query(
      `INSERT INTO subscription_history
         (organization_id, subscription_id, from_plan_id, to_plan_id,
          from_status, to_status, reason, note)
       VALUES ($1, $2, $3, $3, $4, 'past_due', 'payment_failed', $5)`,
      [
        pmt.organization_id,
        pmt.subscription_id,
        sub.plan_id,
        sub.status,
        payment.error_description ?? 'Payment failed',
      ],
    );
  }

  private async _handleRefund(refund: any): Promise<void> {
    await query(
      `UPDATE subscription_payments
       SET status     = 'refunded',
           updated_at = now()
       WHERE razorpay_payment_id = $1`,
      [refund.payment_id],
    );
  }

  // ---- Cancellation -------------------------------------------------------

  /**
   * Marks the subscription to cancel at the end of the current billing period.
   * The org retains full access until current_period_end, after which the
   * downgrade job moves it to 'expired' on the free plan.
   */
  async cancelAtPeriodEnd(organizationId: string, userId: string): Promise<void> {
    const rows = await query<SubRow>(
      `SELECT id, plan_id, status FROM subscriptions WHERE organization_id = $1`,
      [organizationId],
    );
    if (!rows.length) throw new Error('No subscription found for this organization.');
    const sub = rows[0];

    if (sub.status === 'expired' || sub.status === 'cancelled') {
      throw new Error('Subscription is not currently active or trialing.');
    }
    if (sub.status === 'trialing') {
      throw new Error('Trial subscriptions cannot be cancelled — they expire automatically.');
    }

    await query(
      `UPDATE subscriptions
       SET cancel_at_period_end = true,
           cancelled_at         = now(),
           status               = 'cancelled',
           auto_renew           = false,
           updated_at           = now()
       WHERE id = $1`,
      [sub.id],
    );

    await query(
      `INSERT INTO subscription_history
         (organization_id, subscription_id, from_plan_id, to_plan_id,
          from_status, to_status, reason, changed_by_user_id)
       VALUES ($1, $2, $3, $3, $4, 'cancelled', 'cancelled', $5)`,
      [organizationId, sub.id, sub.plan_id, sub.status, userId],
    );
  }

  // ---- Test: Activate Pro without payment ---------------------------------

  /**
   * Directly upgrades an org to a paid Pro plan with no Razorpay charge.
   * Only callable when env.otpBypass is true (test / development mode).
   */
  async testActivatePro(
    organizationId: string,
    planSlug: 'pro_monthly' | 'pro_yearly' = 'pro_monthly',
    billingCycle: 'monthly' | 'yearly' = 'monthly',
  ): Promise<void> {
    if (!env.otpBypass) {
      throw new Error('Test activation is only available when OTP_BYPASS=true.');
    }

    const resolvedSlug =
      billingCycle === 'yearly' || planSlug === 'pro_yearly'
        ? 'pro_yearly'
        : 'pro_monthly';

    const plans = await query<{ id: string }>(
      `SELECT id FROM plans WHERE slug = $1 AND is_active = true`,
      [resolvedSlug],
    );
    if (!plans.length) throw new Error(`Plan '${resolvedSlug}' not found in database.`);
    const planId = plans[0].id;

    const sub = await this.getOrgSubscription(organizationId);
    if (!sub) throw new Error('No subscription record for this organization.');

    const periodEnd = new Date();
    if (resolvedSlug === 'pro_yearly') {
      periodEnd.setFullYear(periodEnd.getFullYear() + 1);
    } else {
      periodEnd.setMonth(periodEnd.getMonth() + 1);
    }

    await query(
      `UPDATE subscriptions
       SET plan_id              = $1,
           status               = 'active',
           current_period_start = now(),
           current_period_end   = $2,
           trial_ends_at        = NULL,
           cancel_at_period_end = false,
           cancelled_at         = NULL,
           grace_period_ends_at = NULL,
           updated_at           = now()
       WHERE id = $3`,
      [planId, periodEnd, sub.id],
    );

    await query(
      `INSERT INTO subscription_history
         (organization_id, subscription_id, from_plan_id, to_plan_id,
          from_status, to_status, reason)
       VALUES ($1, $2, $3, $4, $5, 'active', 'test_activation')`,
      [organizationId, sub.id, sub.plan_id, planId, sub.status],
    );
  }

  // ---- 30-day free trial (no payment) -------------------------------------

  /**
   * True when the org can still claim a 30-day Pro trial from the paywall.
   * Already-trialing / paid orgs, and orgs that already used a trial, are ineligible.
   */
  async canClaimFreeTrial(organizationId: string): Promise<boolean> {
    const sub = await this.getOrgSubscription(organizationId);
    if (!sub) return false;
    if (sub.status === 'trialing' || sub.status === 'active' || sub.status === 'past_due') {
      return false;
    }

    const claimed = await query<{ id: string }>(
      `SELECT id FROM subscription_history
       WHERE organization_id = $1
         AND reason IN ('trial_started', 'trial_claimed')
       LIMIT 1`,
      [organizationId],
    );
    return claimed.length === 0;
  }

  /**
   * Activates a 30-day Pro trial without payment.
   * Org is treated as Premium (pro_trial entitlements) until trial_ends_at.
   */
  async startFreeTrial(organizationId: string, userId: string): Promise<{ trialEndsAt: Date }> {
    const eligible = await this.canClaimFreeTrial(organizationId);
    if (!eligible) {
      throw new Error('Free trial is not available for this organization.');
    }

    const plans = await query<{ id: string; trial_days: number }>(
      `SELECT id, trial_days FROM plans WHERE slug = 'pro_trial' AND is_active = true`,
    );
    if (!plans.length) throw new Error("'pro_trial' plan is missing from the database.");
    const trialPlan = plans[0];
    const trialDays = trialPlan.trial_days > 0 ? trialPlan.trial_days : 30;

    const sub = await this.getOrgSubscription(organizationId);
    if (!sub) throw new Error('No subscription record for this organization.');

    const trialEndsAt = new Date(Date.now() + trialDays * 24 * 60 * 60 * 1000);

    await query(
      `UPDATE subscriptions
       SET plan_id              = $1,
           status               = 'trialing',
           trial_ends_at        = $2,
           current_period_start = now(),
           current_period_end   = $2,
           cancel_at_period_end = false,
           cancelled_at         = NULL,
           grace_period_ends_at = NULL,
           updated_at           = now()
       WHERE id = $3`,
      [trialPlan.id, trialEndsAt, sub.id],
    );

    await query(
      `INSERT INTO subscription_history
         (organization_id, subscription_id, from_plan_id, to_plan_id,
          from_status, to_status, reason, changed_by_user_id)
       VALUES ($1, $2, $3, $4, $5, 'trialing', 'trial_claimed', $6)`,
      [organizationId, sub.id, sub.plan_id, trialPlan.id, sub.status, userId],
    );

    return { trialEndsAt };
  }

  // ---- Public Plans Catalog -----------------------------------------------

  /**
   * Returns all publicly-listed, active plans with their full feature entitlements.
   * Used by the mobile paywall screen. No auth required on the route.
   */
  async getPublicPlans() {
    const withOriginals = `
      SELECT p.id,
             p.slug,
             p.display_name       AS "displayName",
             p.description,
             p.price_inr_monthly  AS "priceInrMonthly",
             p.price_inr_yearly   AS "priceInrYearly",
             p.original_price_inr_monthly AS "originalPriceInrMonthly",
             p.original_price_inr_yearly  AS "originalPriceInrYearly",
             p.trial_days         AS "trialDays",
             p.sort_order         AS "sortOrder",
             json_object_agg(
               f.key,
               CASE WHEN pf.bool_value IS NOT NULL
                    THEN to_json(pf.bool_value)
                    ELSE to_json(pf.quota_value)
               END
             ) AS features
      FROM   plans         p
      JOIN   plan_features pf ON pf.plan_id  = p.id
      JOIN   features      f  ON f.id        = pf.feature_id
      WHERE  p.is_public = true AND p.is_active = true
      GROUP  BY p.id
      ORDER  BY p.sort_order`;

    const withoutOriginals = `
      SELECT p.id,
             p.slug,
             p.display_name       AS "displayName",
             p.description,
             p.price_inr_monthly  AS "priceInrMonthly",
             p.price_inr_yearly   AS "priceInrYearly",
             p.trial_days         AS "trialDays",
             p.sort_order         AS "sortOrder",
             json_object_agg(
               f.key,
               CASE WHEN pf.bool_value IS NOT NULL
                    THEN to_json(pf.bool_value)
                    ELSE to_json(pf.quota_value)
               END
             ) AS features
      FROM   plans         p
      JOIN   plan_features pf ON pf.plan_id  = p.id
      JOIN   features      f  ON f.id        = pf.feature_id
      WHERE  p.is_public = true AND p.is_active = true
      GROUP  BY p.id
      ORDER  BY p.sort_order`;

    try {
      return await query(withOriginals);
    } catch {
      // Migration 010 not applied yet — Flutter falls back to hardcoded strike prices.
      return query(withoutOriginals);
    }
  }

  // ---- Background Job: Downgrade Expired Subscriptions -------------------

  /**
   * Finds all subscriptions whose access period has lapsed and downgrades
   * them to the free plan. Called by the scheduled job every hour.
   * Returns the count of subscriptions downgraded.
   */
  async downgradeExpiredSubscriptions(): Promise<number> {
    const freePlanRows = await query<{ id: string }>(
      `SELECT id FROM plans WHERE slug = 'free' AND is_active = true`,
    );
    if (!freePlanRows.length) return 0;
    const freePlanId = freePlanRows[0].id;

    // Conditions for expiry:
    //   trialing  → trial window closed
    //   past_due  → grace period closed
    //   cancelled → billing period over (user cancelled, access period ended)
    //   active    → billing period over without renewal (missed renewal)
    const expired = await query<{
      id: string;
      organization_id: string;
      plan_id: string;
      status: string;
    }>(
      `SELECT id, organization_id, plan_id, status
       FROM   subscriptions
       WHERE  (status = 'trialing'  AND trial_ends_at        < now())
          OR  (status = 'past_due'  AND grace_period_ends_at < now())
          OR  (status = 'cancelled' AND current_period_end   < now())
          OR  (status = 'active'    AND current_period_end   < now())`,
    );

    for (const sub of expired) {
      await query(
        `UPDATE subscriptions
         SET plan_id              = $1,
             status               = 'expired',
             trial_ends_at        = NULL,
             grace_period_ends_at = NULL,
             updated_at           = now()
         WHERE id = $2`,
        [freePlanId, sub.id],
      );

      const reason =
        sub.status === 'trialing'
          ? 'trial_expired'
          : sub.status === 'cancelled'
          ? 'cancelled'
          : 'payment_failed';

      await query(
        `INSERT INTO subscription_history
           (organization_id, subscription_id, from_plan_id, to_plan_id,
            from_status, to_status, reason)
         VALUES ($1, $2, $3, $4, $5, 'expired', $6)`,
        [sub.organization_id, sub.id, sub.plan_id, freePlanId, sub.status, reason],
      );
    }

    return expired.length;
  }
}
