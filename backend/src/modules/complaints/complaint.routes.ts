// modules/complaints/complaint.routes.ts
import { Router } from 'express';
import { ComplaintController } from './complaint.controller';

const controller = new ComplaintController();
export const complaintRouter = Router({ mergeParams: true });

complaintRouter.get('/', controller.list);
complaintRouter.post('/', controller.create);
complaintRouter.patch('/:complaintId', controller.updateStatus);