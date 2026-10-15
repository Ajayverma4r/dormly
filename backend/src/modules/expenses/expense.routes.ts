// modules/expenses/expense.routes.ts
import { Router } from 'express';
import { ExpenseController } from './expense.controller';
import { requireRole } from '@shared/middleware/auth-guard';

const controller = new ExpenseController();
export const expenseRouter = Router({ mergeParams: true });

expenseRouter.use(requireRole('owner', 'admin', 'manager'));

expenseRouter.get('/', controller.list);
expenseRouter.get('/summary/this-month', controller.totalThisMonth);
expenseRouter.post('/', controller.create);
// A hard delete of a financial record with no audit trail: owners and admins only.
expenseRouter.delete('/:expenseId', requireRole('owner', 'admin'), controller.remove);
