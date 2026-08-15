// modules/subscriptions/subscription.routes.ts
//
// Two separate routers are exported:
//
//   subscriptionRouter  — auth-guarded, mounted at /v1/subscriptions
//   webhookRouter       — NO auth (Razorpay posts here), mounted at /v1/webhooks
//                         MUST be registered in app.ts BEFORE express.json() so
//                         the raw body is available for signature verification.
//                         (We use the express.json({ verify }) approach instead —
//                         see app.ts for the rawBody capture setup.)

import { Router } from 'express';
import { SubscriptionController } from './subscription.controller';
import { authGuard, requireContext, requireRole } from '@shared/middleware/auth-guard';

const controller = new SubscriptionController();

// ---------------------------------------------------------------------------
// Auth-guarded subscription routes
// ---------------------------------------------------------------------------
export const subscriptionRouter = Router();
subscriptionRouter.use(authGuard, requireContext);

// Owner + admin can read the subscription
subscriptionRouter.get('/me',      requireRole('owner', 'admin'), controller.getMySubscription);
subscriptionRouter.get('/history', requireRole('owner', 'admin'), controller.getHistory);

// Only the org owner can initiate payments or cancellations
subscriptionRouter.post('/create-order', requireRole('owner'), controller.createOrder);
subscriptionRouter.post('/cancel',       requireRole('owner'), controller.cancelSubscription);

// ---------------------------------------------------------------------------
// Webhook router (no auth — signature verified inside the handler)
// ---------------------------------------------------------------------------
export const webhookRouter = Router();
webhookRouter.post('/razorpay', controller.razorpayWebhook);

// ---------------------------------------------------------------------------
// Plans catalog router (public — no auth required)
// ---------------------------------------------------------------------------
export const plansRouter = Router();
plansRouter.get('/', controller.getPublicPlans);
