// modules/auth/auth.controller.ts
import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { AuthService } from './auth.service';

const service = new AuthService();

const phoneSchema = z.object({ phone: z.string().min(6) });
const verifySchema = z.object({ phone: z.string().min(6), code: z.string().length(6) });
const refreshSchema = z.object({ refreshToken: z.string() });

export class AuthController {
  requestOtp = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone } = phoneSchema.parse(req.body);
      await service.requestOtp(phone);
      res.status(202).json({ message: 'OTP sent' });
    } catch (err) { next(err); }
  };

  verifyOtp = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, code } = verifySchema.parse(req.body);
      const result = await service.verifyOtp(phone, code);
      res.json({ data: result });
    } catch (err) { next(err); }
  };

  refresh = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { refreshToken } = refreshSchema.parse(req.body);
      const result = await service.refresh(refreshToken);
      res.json({ data: result });
    } catch (err) { next(err); }
  };
}
