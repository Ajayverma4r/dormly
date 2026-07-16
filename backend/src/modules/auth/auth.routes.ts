// modules/auth/auth.routes.ts
import { Router } from 'express';
import { AuthController } from './auth.controller';
import { AuthContextController } from './auth-context.controller';
import { authGuard } from '@shared/middleware/auth-guard';

const controller = new AuthController();
const contextController = new AuthContextController();
export const authRouter = Router();

authRouter.post('/otp/request', controller.requestOtp);
authRouter.post('/otp/verify', controller.verifyOtp);
authRouter.post('/refresh', controller.refresh);

authRouter.get('/contexts', authGuard, contextController.listContexts);
authRouter.post('/contexts/select', authGuard, contextController.selectContext);