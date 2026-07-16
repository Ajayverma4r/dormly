// modules/tenancies/tenancy.routes.ts
import { Router } from 'express';
import { TenancyController } from './tenancy.controller';
import { uploadAgreementMiddleware } from './tenancy.controller';
import { requireRole } from '@shared/middleware/auth-guard';
const controller = new TenancyController();
export const tenancyRouter = Router({ mergeParams: true });

tenancyRouter.get('/', controller.list);
tenancyRouter.post('/', requireRole('owner', 'admin', 'manager'), controller.create);
tenancyRouter.patch('/:tenancyId', requireRole('owner', 'admin', 'manager'), controller.update);
tenancyRouter.post('/:tenancyId/end', requireRole('owner', 'admin', 'manager'), controller.endTenancy);
tenancyRouter.post('/:tenancyId/agreement', requireRole('owner', 'admin', 'manager'), uploadAgreementMiddleware, controller.uploadAgreement);