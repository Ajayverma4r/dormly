// modules/properties/properties.routes.ts
import { Router } from 'express';
import { PropertiesController } from './properties.controller';
import { authGuard, requireContext, requirePropertyAccess } from '@shared/middleware/auth-guard';
import { requireWritableProperty } from '@shared/middleware/require-writable-property';
import { structureRouter } from '@modules/structure/structure.routes';
import { tenancyRouter } from '@modules/tenancies/tenancy.routes';
import { billingRouter } from '@modules/billing/billing.routes';
import { analyticsRouter } from '@modules/analytics/analytics.routes';
import { complaintRouter } from '@modules/complaints/complaint.routes';
import { staffRouter } from '@modules/staff/staff.routes';
import { reportsRouter } from '@modules/reports/reports.routes';

const controller = new PropertiesController();
export const propertiesRouter = Router();

propertiesRouter.use(authGuard, requireContext);
propertiesRouter.get('/', controller.list);
propertiesRouter.get('/:propertyId', controller.getById);
propertiesRouter.post('/', controller.create);

// Nested property APIs: auth + org access, then freeze surplus commercial
// properties for free-tier writes (reads always allowed).
const propertyGuards = [requirePropertyAccess, requireWritableProperty];

propertiesRouter.use('/:propertyId/billing', ...propertyGuards, billingRouter);
propertiesRouter.use('/:propertyId/structure', ...propertyGuards, structureRouter);
propertiesRouter.use('/:propertyId/tenancies', ...propertyGuards, tenancyRouter);
propertiesRouter.use('/:propertyId/analytics', ...propertyGuards, analyticsRouter);
propertiesRouter.use('/:propertyId/complaints', ...propertyGuards, complaintRouter);
propertiesRouter.use('/:propertyId/staff', ...propertyGuards, staffRouter);
propertiesRouter.use('/:propertyId/reports', ...propertyGuards, reportsRouter);