// modules/billing/billing.routes.ts
import { Router } from 'express';
import { BillingController } from './billing.controller';
import { requireRole } from '@shared/middleware/auth-guard';

const controller = new BillingController();
export const billingRouter = Router({ mergeParams: true });
billingRouter.use(requireRole('owner', 'admin', 'manager')); // Staff has no billing access at all, per role matrix

billingRouter.get('/charge-types', controller.listChargeTypes);
billingRouter.post('/charge-types', controller.createChargeType);
billingRouter.delete('/charge-types/:chargeTypeId', controller.deleteChargeType);

billingRouter.get('/invoices', controller.listInvoices);
billingRouter.get('/invoices/:invoiceId', controller.getInvoice);
billingRouter.post('/invoices', controller.createInvoice);
billingRouter.post('/invoices/:invoiceId/payments', controller.recordPayment);
billingRouter.post('/invoices/:invoiceId/remind', controller.sendReminder);