// modules/billing/billing.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { BillingService } from './billing.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new BillingService();

const chargeKindSchema = z
  .enum(['rent', 'electricity', 'maintenance', 'previous_dues', 'other'])
  .optional();

const createChargeTypeSchema = z.object({
  name: z.string().min(1),
  defaultAmount: z.number().default(0),
  isRecurring: z.boolean().default(true),
});

const lineItemsSchema = z.array(
  z.object({
    chargeTypeId: z.string().uuid().optional(),
    description: z.string().min(1),
    amount: z.number(),
    chargeKind: chargeKindSchema,
  }),
);

const createInvoiceSchema = z
  .object({
    tenancyId: z.string().uuid(),
    periodStart: z.string(),
    periodEnd: z.string(),
    dueDate: z.string(),
    lineItems: lineItemsSchema.default([]),
    includeArrears: z.boolean().optional(),
    includePendingCharges: z.boolean().optional(),
  })
  .refine(
    (d) =>
      d.lineItems.length > 0 ||
      d.includeArrears === true ||
      d.includePendingCharges !== false,
    { message: 'Provide line items or enable arrears / pending charges' },
  );

const updateInvoiceSchema = z.object({
  periodStart: z.string(),
  periodEnd: z.string(),
  dueDate: z.string(),
  lineItems: lineItemsSchema.min(1),
});

const generateMonthlySchema = z.object({
  tenancyId: z.string().uuid(),
  includeArrears: z.boolean().optional(),
  includePendingCharges: z.boolean().optional(),
  periodStart: z.string().optional(),
  periodEnd: z.string().optional(),
  dueDate: z.string().optional(),
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
    } catch (err) {
      next(err);
    }
  };

  createChargeType = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createChargeTypeSchema.parse(req.body);
      const chargeType = await service.createChargeType(
        req.params.propertyId,
        body.name,
        body.defaultAmount,
        body.isRecurring,
      );
      res.status(201).json({ data: chargeType });
    } catch (err) {
      next(err);
    }
  };

  deleteChargeType = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      await service.deleteChargeType(req.params.chargeTypeId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  listInvoices = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  cashflowSummary = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const receivedThisMonth = await service.receivedThisMonth(req.params.propertyId);
      res.json({ data: { receivedThisMonth } });
    } catch (err) {
      next(err);
    }
  };

  listPayments = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listPaymentsByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  getInvoice = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const invoice = await service.getById(req.params.invoiceId);
      if (!invoice) return res.status(404).json({ error: 'Invoice not found' });
      res.json({ data: invoice });
    } catch (err) {
      next(err);
    }
  };

  arrearsPreview = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const periodStart =
        (req.query.periodStart as string | undefined)?.slice(0, 10) ||
        (() => {
          const n = new Date();
          return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}-01`;
        })();
      const rentRaw = req.query.monthlyRent ?? req.query.monthly_rent;
      const monthlyRentOverride =
        rentRaw != null && String(rentRaw).trim() !== ''
          ? Number(rentRaw)
          : undefined;
      const data = await service.computeUnbilledArrears(
        req.params.tenancyId,
        periodStart,
        Number.isFinite(monthlyRentOverride) ? monthlyRentOverride : undefined,
      );
      res.json({ data });
    } catch (err) {
      next(err);
    }
  };

  createInvoice = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createInvoiceSchema.parse(req.body);
      const invoice = await service.createInvoice({
        propertyId: req.params.propertyId,
        ...body,
      });
      res.status(201).json({ data: invoice });
    } catch (err) {
      next(err);
    }
  };

  generateMonthlyInvoice = async (
    req: AuthedRequest,
    res: Response,
    next: NextFunction,
  ) => {
    try {
      const body = generateMonthlySchema.parse(req.body);
      const invoice = await service.generateMonthlyInvoice({
        propertyId: req.params.propertyId,
        ...body,
      });
      res.status(201).json({ data: invoice });
    } catch (err) {
      next(err);
    }
  };

  addPendingCharges = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancyId = z.string().uuid().parse(req.body.tenancyId);
      const result = await service.addPendingChargesToInvoice(
        tenancyId,
        req.params.invoiceId,
      );
      const invoice = await service.getById(req.params.invoiceId);
      res.json({ data: { ...result, invoice } });
    } catch (err) {
      next(err);
    }
  };

  updateInvoice = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = updateInvoiceSchema.parse(req.body);
      const invoice = await service.updateInvoice(
        req.params.invoiceId,
        req.params.propertyId,
        body,
      );
      if (!invoice) return res.status(404).json({ error: 'Invoice not found' });
      res.json({ data: invoice });
    } catch (err) {
      next(err);
    }
  };

  recordPayment = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = paymentSchema.parse(req.body);
      const invoice = await service.recordPayment(
        req.params.invoiceId,
        body.amount,
        body.method,
        body.note,
        req.userId!,
      );
      res.json({ data: invoice });
    } catch (err) {
      next(err);
    }
  };

  sendReminder = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.sendReminder(req.params.invoiceId) });
    } catch (err) {
      next(err);
    }
  };

  myInvoices = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByTenancy(req.ctxId!) });
    } catch (err) {
      next(err);
    }
  };
}
