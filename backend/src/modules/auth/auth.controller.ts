// modules/auth/auth.controller.ts
import path from 'path';
import fs from 'fs';
import multer from 'multer';
import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { AuthService } from './auth.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new AuthService();

const phoneSchema = z.object({ phone: z.string().min(6) });
const verifySchema = z.object({ phone: z.string().min(6), code: z.string().length(6) });
const refreshSchema = z.object({ refreshToken: z.string() });
const updateProfileSchema = z.object({
  name: z.string().min(2).max(120).optional(),
  email: z.string().email().nullable().optional().or(z.literal('')),
  avatarUrl: z.string().nullable().optional(),
});

const avatarDir = path.join(__dirname, '../../../uploads/avatars');
fs.mkdirSync(avatarDir, { recursive: true });

const avatarStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, avatarDir),
  filename: (req, file, cb) => {
    const userId = (req as AuthedRequest).userId ?? 'anon';
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${userId}-${Date.now()}${ext}`);
  },
});

export const uploadAvatarMiddleware = multer({
  storage: avatarStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image uploads are allowed.'));
    }
    cb(null, true);
  },
}).single('avatar');

export class AuthController {
  requestOtp = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone } = phoneSchema.parse(req.body);
      await service.requestOtp(phone);
      res.status(202).json({ message: 'OTP sent' });
    } catch (err) {
      next(err);
    }
  };

  verifyOtp = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, code } = verifySchema.parse(req.body);
      const result = await service.verifyOtp(phone, code);
      res.json({ data: result });
    } catch (err) {
      next(err);
    }
  };

  refresh = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { refreshToken } = refreshSchema.parse(req.body);
      const result = await service.refresh(refreshToken);
      res.json({ data: result });
    } catch (err) {
      next(err);
    }
  };

  getMe = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const profile = await service.getProfile(req.userId!);
      res.json({ data: profile });
    } catch (err) {
      next(err);
    }
  };

  updateMe = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = updateProfileSchema.parse(req.body ?? {});
      const email =
        body.email === '' || body.email === undefined ? body.email : body.email;
      const profile = await service.updateProfile(req.userId!, {
        name: body.name,
        email: email === '' ? null : email,
        avatarUrl: body.avatarUrl,
      });
      res.json({ data: profile });
    } catch (err) {
      next(err);
    }
  };

  uploadAvatar = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: 'No avatar file uploaded.' });
      }
      const avatarUrl = `/uploads/avatars/${req.file.filename}`;
      const profile = await service.updateProfile(req.userId!, { avatarUrl });
      res.json({ data: profile });
    } catch (err) {
      next(err);
    }
  };
}
