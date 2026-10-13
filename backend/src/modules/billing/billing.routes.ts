// modules/billing/billing.routes.ts
import { Router } from 'express';
import { BillingController } from './billing.controller';
import { requireRole } from '@shared/middleware/auth-guard';
import { scopeParamToProperty } from '@shared/middleware/property-scope';

const controller = new BillingController();
export const billingRouter = Router({ mergeParams: true });
billingRouter.use(requireRole('owner', 'admin', 'manager')); // Staff has no billing access at all, per role matrix
billingRouter.param('invoiceId', scopeParamToProperty('invoices'));
billingRouter.param('tenancyId', scopeParamToProperty('tenancies'));
billingRouter.param('chargeTypeId', scopeParamToProperty('charge_types'));

billingRouter.get('/charge-types', controller.listChargeTypes);
billingRouter.post('/charge-types', controller.createChargeType);
billingRouter.delete('/charge-types/:chargeTypeId', controller.deleteChargeType);

billingRouter.get('/cashflow-summary', controller.cashflowSummary);
billingRouter.get('/payments', controller.listPayments);
billingRouter.get('/tenancies/:tenancyId/arrears-preview', controller.arrearsPreview);
billingRouter.get('/invoices', controller.listInvoices);
billingRouter.post('/invoices/generate-monthly', controller.generateMonthlyInvoice);
billingRouter.get('/invoices/:invoiceId', controller.getInvoice);
billingRouter.post('/invoices', controller.createInvoice);
billingRouter.patch('/invoices/:invoiceId', controller.updateInvoice);
billingRouter.patch('/invoices/:invoiceId/due-date', controller.updateDueDate);
billingRouter.post('/invoices/:invoiceId/send', controller.sendInvoice);
billingRouter.post('/invoices/:invoiceId/payments', controller.recordPayment);
billingRouter.post('/invoices/:invoiceId/pending-charges', controller.addPendingCharges);
billingRouter.post('/invoices/:invoiceId/remind', controller.sendReminder);
