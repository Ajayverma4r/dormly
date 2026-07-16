// modules/billing/billing.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { BillingService } from './billing.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new BillingService();

const createChargeTypeSchema = z.object({
  name: z.string().min(1),
  defaultAmount: z.number().default(0),
  isRecurring: z.boolean().default(true),
});

const createInvoiceSchema = z.object({
  tenancyId: z.string().uuid(),
  periodStart: z.string(),
  periodEnd: z.string(),
  dueDate: z.string(),
  lineItems: z.array(z.object({
    chargeTypeId: z.string().uuid().optional(),
    description: z.string().min(1),
    amount: z.number(),
  })).min(1),
});

const paymentSchema = z.object({
  amount: z.number().positive(),
  method: z.string().default('cash'),
  note: z.string().optional(),
});

export class BillingController {
  listChargeTypes = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listChargeTypes(req.params.propertyId) });
    } catch (err) { next(err); }
  };

  createChargeType = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createChargeTypeSchema.parse(req.body);
      const chargeType = await service.createChargeType(req.params.propertyId, body.name, body.defaultAmount, body.isRecurring);
      res.status(201).json({ data: chargeType });
    } catch (err) { next(err); }
  };

  deleteChargeType = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      await service.deleteChargeType(req.params.chargeTypeId);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  listInvoices = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) { next(err); }
  };

  getInvoice = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const invoice = await service.getById(req.params.invoiceId);
      if (!invoice) return res.status(404).json({ error: 'Invoice not found' });
      res.json({ data: invoice });
    } catch (err) { next(err); }
  };

  createInvoice = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createInvoiceSchema.parse(req.body);
      const invoice = await service.createInvoice({ propertyId: req.params.propertyId, ...body });
      res.status(201).json({ data: invoice });
    } catch (err) { next(err); }
  };

  recordPayment = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = paymentSchema.parse(req.body);
      const invoice = await service.recordPayment(
        req.params.invoiceId, body.amount, body.method, body.note, req.userId!,
      );
      res.json({ data: invoice });
    } catch (err) { next(err); }
  };

  sendReminder = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.sendReminder(req.params.invoiceId) });
    } catch (err) { next(err); }
  };

  myInvoices = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByTenancy(req.ctxId!) });
    } catch (err) { next(err); }
  };
}