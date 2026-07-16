// modules/tenant-portal/tenant-portal.routes.ts
import { Router } from 'express';
import { TenantPortalController } from './tenant-portal.controller';
import { BillingController } from '@modules/billing/billing.controller';
import { ComplaintController } from '@modules/complaints/complaint.controller';
import { authGuard, requireContext, requireRole } from '@shared/middleware/auth-guard';

const controller = new TenantPortalController();
const billingController = new BillingController();
const complaintController = new ComplaintController();
export const tenantPortalRouter = Router();

tenantPortalRouter.use(authGuard, requireContext, requireRole('tenant'));
tenantPortalRouter.get('/me', controller.getMe);
tenantPortalRouter.get('/invoices', billingController.myInvoices);
tenantPortalRouter.get('/complaints', complaintController.myComplaints);
tenantPortalRouter.post('/complaints', complaintController.createMine);