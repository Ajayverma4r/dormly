// modules/complaints/complaint.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import multer from 'multer';
import { ComplaintService } from './complaint.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { safeImageExtension, saveUpload } from '@shared/storage/file-storage';

const service = new ComplaintService();

export const uploadComplaintPhotosMiddleware = multer({
  storage: multer.memoryStorage(),
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

async function filesToUrls(req: AuthedRequest): Promise<string[]> {
  const files = (req.files as Express.Multer.File[] | undefined) ?? [];
  return Promise.all(
    files.map((f) =>
      saveUpload(
        'complaints',
        `${Date.now()}-${Math.random().toString(36).slice(2)}${safeImageExtension(f.originalname)}`,
        f,
      ),
    ),
  );
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
      const photoUrls = [...(body.photoUrls ?? []), ...(await filesToUrls(req))];
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
      const photoUrls = [...(body.photoUrls ?? []), ...(await filesToUrls(req))];
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
