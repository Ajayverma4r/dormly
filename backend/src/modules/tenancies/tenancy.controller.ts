// modules/tenancies/tenancy.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { TenancyService } from './tenancy.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import multer from 'multer';
import path from 'path';
import fs from 'fs';

const uploadDir = path.join(__dirname, '../../../uploads/agreements');
fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (req, _file, cb) => cb(null, `${req.params.tenancyId}-${Date.now()}.pdf`),
});

export const uploadAgreementMiddleware = multer({
  storage,
  fileFilter: (_req, file, cb) => {
    if (file.mimetype !== 'application/pdf') {
      return cb(new Error('Only PDF files are allowed'));
    }
    cb(null, true);
  },
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
}).single('agreement');

const service = new TenancyService();

const createSchema = z.object({
  nodeId: z.string().uuid(),
  phone: z.string().min(6),
  fullName: z.string().min(1),
  email: z.string().email().optional(),
  address: z.string().optional(),
  companyName: z.string().optional(),
  aadhaarNumber: z.string().optional(),
  moveInAt: z.string().optional(),
  securityDeposit: z.number().optional(),
  notes: z.string().optional(),
});

export class TenancyController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const data = req.query.nodeId
        ? await service.listByNode(req.query.nodeId as string)
        : await service.listByProperty(req.params.propertyId);
      res.json({ data });
    } catch (err) { next(err); }
  };

  create = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createSchema.parse(req.body);
      const tenancy = await service.create({ propertyId: req.params.propertyId, ...body });
      res.status(201).json({ data: tenancy });
    } catch (err) { next(err); }
  };

  update = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.update(req.params.tenancyId, req.body);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  uploadAgreement = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
      const url = `/uploads/agreements/${req.file.filename}`;
      const tenancy = await service.setAgreementUrl(req.params.tenancyId, url);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  endTenancy = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.endTenancy(req.params.tenancyId);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };
}