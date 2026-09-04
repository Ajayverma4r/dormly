// modules/expenses/expense.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { ExpenseService } from './expense.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new ExpenseService();

const createSchema = z.object({
  title: z.string().min(1),
  amount: z.number().positive(),
  expenseDate: z.string().optional(),
  category: z
    .enum(['maintenance', 'utilities', 'salaries', 'supplies', 'taxes', 'other'])
    .optional(),
});

export class ExpenseController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  totalThisMonth = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const total = await service.totalThisMonth(req.params.propertyId);
      res.json({ data: { totalThisMonth: total } });
    } catch (err) {
      next(err);
    }
  };

  create = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createSchema.parse(req.body);
      const expense = await service.create(req.params.propertyId, req.userId!, {
        title: body.title,
        amount: body.amount,
        expenseDate: body.expenseDate,
        category: body.category,
      });
      res.status(201).json({ data: expense });
    } catch (err) {
      next(err);
    }
  };
}
