// modules/tenant-portal/tenant-portal.routes.ts
import { Router } from 'express';
import { TenantPortalController } from './tenant-portal.controller';
import { BillingController } from '@modules/billing/billing.controller';
import {
  ComplaintController,
  uploadComplaintPhotosMiddleware,
} from '@modules/complaints/complaint.controller';
import { MessMenuController } from '@modules/mess-menu/mess-menu.controller';
import {
  MeterReadingsController,
  uploadMeterImageMiddleware,
} from '@modules/meter-readings/meter-readings.controller';
import { GatePassesController } from '@modules/gate-passes/gate-passes.controller';
import { authGuard, requireContext, requireRole } from '@shared/middleware/auth-guard';

const controller = new TenantPortalController();
const billingController = new BillingController();
const complaintController = new ComplaintController();
const messMenuController = new MessMenuController();
const meterController = new MeterReadingsController();
const gatePassesController = new GatePassesController();
export const tenantPortalRouter = Router();

tenantPortalRouter.use(authGuard, requireContext, requireRole('tenant'));
tenantPortalRouter.get('/me', controller.getMe);
tenantPortalRouter.post('/move-out-request', controller.requestMoveOut);
tenantPortalRouter.get('/invoices', billingController.myInvoices);
tenantPortalRouter.get('/complaints', complaintController.myComplaints);
tenantPortalRouter.post(
  '/complaints',
  uploadComplaintPhotosMiddleware,
  complaintController.createMine,
);
tenantPortalRouter.get('/mess-menu', messMenuController.myMenu);
tenantPortalRouter.get('/meter-readings', meterController.myReadings);
tenantPortalRouter.post(
  '/meter-readings',
  uploadMeterImageMiddleware,
  meterController.submitMine,
);
tenantPortalRouter.get('/gate-passes', gatePassesController.myList);
tenantPortalRouter.post('/gate-passes', gatePassesController.createMine);
tenantPortalRouter.get('/society-notices', controller.societyNotices);
tenantPortalRouter.get('/lease-details', controller.leaseDetails);
