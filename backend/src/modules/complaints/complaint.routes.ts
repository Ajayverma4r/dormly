// modules/complaints/complaint.routes.ts
import { Router } from 'express';
import {
  ComplaintController,
  uploadComplaintPhotosMiddleware,
} from './complaint.controller';

const controller = new ComplaintController();
export const complaintRouter = Router({ mergeParams: true });

complaintRouter.get('/', controller.list);
complaintRouter.post('/', uploadComplaintPhotosMiddleware, controller.create);
complaintRouter.patch('/:complaintId', controller.updateStatus);
