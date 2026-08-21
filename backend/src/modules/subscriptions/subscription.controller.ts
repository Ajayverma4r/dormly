// modules/subscriptions/subscription.controller.ts

import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { SubscriptionService } from './subscription.service';
import { EntitlementService } from './entitlement.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const subscriptionService = new SubscriptionService();
const entitlementService = new EntitlementService();

const createOrderSchema = z.object({
  planSlug: z.enum(['pro_monthly', 'pro_yearly']),
  billingCycle: z.enum(['monthly', 'yearly']),
});

const testActivateSchema = z.object({
  planSlug: z.enum(['pro_monthly', 'pro_yearly']).optional().default('pro_monthly'),
  billingCycle: z.enum(['monthly', 'yearly']).optional().default('monthly'),
});

export class SubscriptionController {
  /**
   * GET /v1/subscriptions/me
   * Returns the org's current subscription state and full entitlement snapshot.
   * Used by the frontend to render plan badges, feature gates, and upgrade CTAs.
   */
  getMySubscription = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const orgId = req.ctxId!;
      const [subscription, entitlements, trialEligible] = await Promise.all([
        subscriptionService.getOrgSubscription(orgId),
        entitlementService.getOrgEntitlements(orgId),
        subscriptionService.canClaimFreeTrial(orgId),
      ]);
      res.json({ data: { subscription, entitlements, trialEligible } });
    } catch (err) {
      next(err);
    }
  };

  /**
   * GET /v1/subscriptions/history
   * Returns the last 50 subscription change events for the org.
   */
  getHistory = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const history = await subscriptionService.getSubscriptionHistory(req.ctxId!);
      res.json({ data: history });
    } catch (err) {
      next(err);
    }
  };

  /**
   * POST /v1/subscriptions/create-order
   * Creates a Razorpay order. The client uses the returned orderId + keyId
   * to open the Razorpay checkout modal.
   *
   * Body: { planSlug: 'pro_monthly' | 'pro_yearly', billingCycle: 'monthly' | 'yearly' }
   */
  createOrder = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createOrderSchema.parse(req.body);
      const result = await subscriptionService.createOrder(
        req.ctxId!,
        body.planSlug,
        body.billingCycle,
        req.userId!,
      );
      res.status(201).json({ data: result });
    } catch (err) {
      next(err);
    }
  };

  /**
   * POST /v1/subscriptions/test-activate
   * DEV / TEST only — only works when OTP_BYPASS=true on the server.
   * Body: { planSlug?, billingCycle? } — upgrades without Razorpay.
   */
  testActivatePro = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = testActivateSchema.parse(req.body ?? {});
      await subscriptionService.testActivatePro(
        req.ctxId!,
        body.planSlug,
        body.billingCycle,
      );
      res.json({ data: { activated: true } });
    } catch (err) {
      next(err);
    }
  };

  /**
   * POST /v1/subscriptions/start-trial
   * Claims a 30-day Pro trial (no payment). Once per organization.
   */
  startFreeTrial = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const result = await subscriptionService.startFreeTrial(req.ctxId!, req.userId!);
      res.json({ data: { activated: true, trialEndsAt: result.trialEndsAt } });
    } catch (err) {
      next(err);
    }
  };

  /**
   * GET /v1/plans
   * Public endpoint — no auth. Returns the plan catalog with per-plan feature
   * entitlements so the mobile paywall screen can build a comparison table
   * dynamically without hardcoding plan names.
   */
  getPublicPlans = async (_req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const plans = await subscriptionService.getPublicPlans();
      res.json({ data: plans });
    } catch (err) {
      next(err);
    }
  };

  /**
   * POST /v1/subscriptions/cancel
   * Cancels the subscription at the end of the current billing period.
   * The org retains full Pro access until current_period_end.
   * No refund is issued — direct the user to support for mid-cycle refunds.
   */
  cancelSubscription = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      await subscriptionService.cancelAtPeriodEnd(req.ctxId!, req.userId!);
      res.json({ data: { cancelled: true } });
    } catch (err) {
      next(err);
    }
  };

  /**
   * POST /v1/webhooks/razorpay
   * Razorpay → server. No auth header — signature verified via HMAC-SHA256.
   *
   * Requires the raw request body (configured in app.ts via express.json verify).
   * Returns 200 on success or known idempotent events.
   * Returns 400 on signature mismatch (Razorpay will NOT retry 4xx).
   * Returns 500 on internal errors (Razorpay will retry with exponential backoff).
   */
  razorpayWebhook = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const signature = req.headers['x-razorpay-signature'] as string | undefined;
      if (!signature) {
        return res.status(400).json({ error: 'Missing X-Razorpay-Signature header.' });
      }

      const rawBody = (req as any).rawBody as Buffer | undefined;
      if (!rawBody || !Buffer.isBuffer(rawBody)) {
        return res.status(500).json({ error: 'Raw body unavailable. Check express.json verify config.' });
      }

      await subscriptionService.handleWebhookEvent(rawBody, signature);
      res.json({ received: true });
    } catch (err) {
      if (err instanceof Error && err.message.includes('signature')) {
        // 400 stops Razorpay retrying — correct for bad signatures
        return res.status(400).json({ error: err.message });
      }
      // 500 causes Razorpay to retry — correct for transient DB errors
      next(err);
    }
  };
}
