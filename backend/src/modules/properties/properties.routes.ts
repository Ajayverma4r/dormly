// modules/properties/properties.routes.ts
import { Router } from 'express';
import { PropertiesController } from './properties.controller';
import { authGuard, requireContext, requirePropertyAccess } from '@shared/middleware/auth-guard';
import { structureRouter } from '@modules/structure/structure.routes';
import { tenancyRouter } from '@modules/tenancies/tenancy.routes';
import { billingRouter } from '@modules/billing/billing.routes';
import { analyticsRouter } from '@modules/analytics/analytics.routes';
import { complaintRouter } from '@modules/complaints/complaint.routes';
import { staffRouter } from '@modules/staff/staff.routes';

const controller = new PropertiesController();
export const propertiesRouter = Router();

propertiesRouter.use(authGuard, requireContext);
propertiesRouter.get('/', controller.list);
propertiesRouter.get('/:propertyId', controller.getById);
propertiesRouter.post('/', controller.create);
propertiesRouter.use('/:propertyId/billing', requirePropertyAccess, billingRouter);
propertiesRouter.use('/:propertyId/structure', requirePropertyAccess, structureRouter);
propertiesRouter.use('/:propertyId/tenancies', requirePropertyAccess, tenancyRouter);
propertiesRouter.use('/:propertyId/analytics', requirePropertyAccess, analyticsRouter);
propertiesRouter.use('/:propertyId/complaints', requirePropertyAccess, complaintRouter);
propertiesRouter.use('/:propertyId/staff', requirePropertyAccess, staffRouter);