// app.ts
import express, { Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'path';
import { authRouter } from '@modules/auth/auth.routes';
import { propertiesRouter } from '@modules/properties/properties.routes';
import { propertyTypesRouter } from '@modules/properties/property-types.routes';
import { errorHandler } from '@shared/middleware/error-handler';
import { tenantPortalRouter } from '@modules/tenant-portal/tenant-portal.routes';
import { orgAnalyticsRouter } from '@modules/analytics/org-analytics.routes';
import { notificationsRouter } from '@modules/notifications/notifications.routes';
import { invitationsRouter } from '@modules/staff/invitations.routes';
import { subscriptionRouter, webhookRouter, plansRouter } from '@modules/subscriptions/subscription.routes';
import { scheduleSubscriptionDowngradeJob } from '@shared/jobs/subscription-downgrade.job';

export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(cors());

  // Capture the raw body buffer on every request so the Razorpay webhook
  // handler can verify the HMAC-SHA256 signature. The parsed JSON body is
  // still available on req.body as normal for all other routes.
  app.use(
    express.json({
      verify: (req: Request & { rawBody?: Buffer }, _res, buf) => {
        req.rawBody = buf;
      },
    }),
  );

  app.get('/health', (_req, res: Response) => res.json({ status: 'ok' }));

  app.use('/v1/auth',                                    authRouter);
  app.use('/v1/property-types',                          propertyTypesRouter);
  app.use('/v1/properties',                              propertiesRouter);
  app.use('/v1/tenant-portal',                           tenantPortalRouter);
  app.use('/v1/notifications',                           notificationsRouter);
  app.use('/v1/invitations',                             invitationsRouter);
  app.use('/v1/organizations/:organizationId/analytics', orgAnalyticsRouter);
  app.use('/v1/subscriptions',                           subscriptionRouter);
  app.use('/v1/plans',                                   plansRouter);
  // Razorpay webhooks — no JWT auth, signature verified inside the handler
  app.use('/v1/webhooks',                                webhookRouter);

  app.use('/uploads', express.static(path.join(__dirname, '../uploads')));
  app.use(errorHandler);

  // Start the subscription expiry job (runs every hour)
  scheduleSubscriptionDowngradeJob();

  return app;
}
