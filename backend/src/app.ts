// app.ts
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { authRouter } from '@modules/auth/auth.routes';
import { propertiesRouter } from '@modules/properties/properties.routes';
import { propertyTypesRouter } from '@modules/properties/property-types.routes';
import { errorHandler } from '@shared/middleware/error-handler';
import { tenantPortalRouter } from '@modules/tenant-portal/tenant-portal.routes';
import { orgAnalyticsRouter } from '@modules/analytics/org-analytics.routes';
import { notificationsRouter } from '@modules/notifications/notifications.routes';
import path from 'path';
import { invitationsRouter } from '@modules/staff/invitations.routes';
export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(cors());
  app.use(express.json());
  app.use('/v1/notifications', notificationsRouter);
  app.get('/health', (_req, res) => res.json({ status: 'ok' }));
  app.use('/v1/organizations/:organizationId/analytics', orgAnalyticsRouter);
  app.use('/v1/auth', authRouter);
  app.use('/v1/property-types', propertyTypesRouter);
  app.use('/v1/properties', propertiesRouter);
  app.use('/v1/tenant-portal', tenantPortalRouter);
  app.use(errorHandler);
  app.use('/v1/invitations', invitationsRouter);
  app.use('/uploads', express.static(path.join(__dirname, '../uploads')));
  return app;
}
