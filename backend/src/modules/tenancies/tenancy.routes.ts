// modules/tenancies/tenancy.routes.ts
import { Router } from 'express';
import { TenancyController } from './tenancy.controller';
import { uploadAgreementMiddleware, uploadProfilePhotoMiddleware, uploadTenantDocumentMiddleware } from './tenancy.controller';
import { requirePropertyManager, requirePropertyTeam, requireRole } from '@shared/middleware/auth-guard';
import { scopeParamToProperty } from '@shared/middleware/property-scope';
const controller = new TenancyController();
export const tenancyRouter = Router({ mergeParams: true });
tenancyRouter.param('tenancyId', scopeParamToProperty('tenancies'));

// Tenants use /tenant-portal; staff get records without KYC or rent details.
tenancyRouter.get('/', requirePropertyTeam, controller.list);
tenancyRouter.get('/:tenancyId', requirePropertyTeam, controller.getById);
// KYC documents (Aadhaar, PAN, agreements) are for owners, admins and managers only.
tenancyRouter.get('/:tenancyId/documents', requirePropertyManager, controller.listDocuments);
tenancyRouter.get(
  '/:tenancyId/documents/:documentId/file',
  requirePropertyManager,
  controller.documentFile,
);
tenancyRouter.post('/', requireRole('owner', 'admin', 'manager'), controller.create);
tenancyRouter.patch('/:tenancyId', requireRole('owner', 'admin', 'manager'), controller.update);
tenancyRouter.post('/:tenancyId/end', requireRole('owner', 'admin', 'manager'), controller.endTenancy);
tenancyRouter.post('/:tenancyId/move-out-request/review', requireRole('owner', 'admin', 'manager'), controller.reviewMoveOutRequest);
tenancyRouter.post('/:tenancyId/agreement', requireRole('owner', 'admin', 'manager'), uploadAgreementMiddleware, controller.uploadAgreement);
tenancyRouter.post('/:tenancyId/profile-photo', requireRole('owner', 'admin', 'manager'), uploadProfilePhotoMiddleware, controller.uploadProfilePhoto);
tenancyRouter.post('/:tenancyId/documents', requireRole('owner', 'admin', 'manager'), uploadTenantDocumentMiddleware, controller.uploadDocument);
