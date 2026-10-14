// modules/complaints/complaint.routes.ts
import { Router } from 'express';
import {
  ComplaintController,
  uploadComplaintPhotosMiddleware,
} from './complaint.controller';
import { requireRole } from '@shared/middleware/auth-guard';
import { scopeParamToProperty } from '@shared/middleware/property-scope';

const controller = new ComplaintController();
export const complaintRouter = Router({ mergeParams: true });

complaintRouter.param('complaintId', scopeParamToProperty('complaints'));

// Tenants reaching the property list only get the complaints they raised.
complaintRouter.get('/', controller.list);
complaintRouter.post('/', uploadComplaintPhotosMiddleware, controller.create);
complaintRouter.get(
  '/assignees',
  requireRole('owner', 'admin', 'manager'),
  controller.assignees,
);
complaintRouter.patch(
  '/:complaintId',
  requireRole('owner', 'admin', 'manager', 'staff'),
  controller.updateStatus,
);
// Team, or the tenant who raised the complaint; the controller decides which entries they see.
complaintRouter.get('/:complaintId/comments', controller.listComments);
complaintRouter.post('/:complaintId/comments', controller.addComment);
complaintRouter.put(
  '/:complaintId/assignment',
  requireRole('owner', 'admin', 'manager'),
  controller.assign,
);
