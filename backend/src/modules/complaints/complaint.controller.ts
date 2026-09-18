// modules/complaints/complaint.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import fs from 'fs';
import path from 'path';
import multer from 'multer';
import { ComplaintService } from './complaint.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new ComplaintService();

const photoDir = path.join(__dirname, '../../../uploads/complaints');
fs.mkdirSync(photoDir, { recursive: true });

const photoStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, photoDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2)}${ext}`);
  },
});

export const uploadComplaintPhotosMiddleware = multer({
  storage: photoStorage,
  limits: { fileSize: 8 * 1024 * 1024, files: 3 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image uploads are allowed'));
    }
    cb(null, true);
  },
}).array('photos', 3);

const createSchema = z.object({
  nodeId: z.string().uuid(),
  category: z.string().min(1),
  description: z.string().min(1),
  priority: z.enum(['low', 'medium', 'high']).default('medium'),
  photoUrls: z.array(z.string()).optional(),
});

const updateSchema = z.object({
  status: z.enum(['open', 'assigned', 'in_progress', 'resolved', 'closed']),
  resolutionNote: z.string().optional(),
});

function filesToUrls(req: AuthedRequest): string[] {
  const files = (req.files as Express.Multer.File[] | undefined) ?? [];
  return files.map((f) => `/uploads/complaints/${f.filename}`);
}

export class ComplaintController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  create = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createSchema.parse({
        ...req.body,
        photoUrls: req.body.photoUrls
          ? typeof req.body.photoUrls === 'string'
            ? JSON.parse(req.body.photoUrls)
            : req.body.photoUrls
          : undefined,
      });
      const photoUrls = [...(body.photoUrls ?? []), ...filesToUrls(req)];
      const complaint = await service.create(
        req.params.propertyId,
        body.nodeId,
        req.userId!,
        body.category,
        body.description,
        body.priority,
        photoUrls,
      );
      res.status(201).json({ data: complaint });
    } catch (err) {
      next(err);
    }
  };

  updateStatus = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = updateSchema.parse(req.body);
      const complaint = await service.updateStatus(
        req.params.complaintId,
        body.status,
        body.resolutionNote,
      );
      if (!complaint) return res.status(404).json({ error: 'Complaint not found' });
      res.json({ data: complaint });
    } catch (err) {
      next(err);
    }
  };

  myComplaints = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByUser(req.userId!) });
    } catch (err) {
      next(err);
    }
  };

  createMine = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = z
        .object({
          category: z.string().min(1),
          description: z.string().min(1),
          priority: z.enum(['low', 'medium', 'high']).default('medium'),
          propertyId: z.string().uuid(),
          nodeId: z.string().uuid(),
          photoUrls: z.array(z.string()).optional(),
        })
        .parse({
          ...req.body,
          photoUrls: req.body.photoUrls
            ? typeof req.body.photoUrls === 'string'
              ? JSON.parse(req.body.photoUrls)
              : req.body.photoUrls
            : undefined,
        });
      const photoUrls = [...(body.photoUrls ?? []), ...filesToUrls(req)];
      const complaint = await service.create(
        body.propertyId,
        body.nodeId,
        req.userId!,
        body.category,
        body.description,
        body.priority,
        photoUrls,
      );
      res.status(201).json({ data: complaint });
    } catch (err) {
      next(err);
    }
  };
}
