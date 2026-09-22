// modules/meter-readings/meter-readings.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import fs from 'fs';
import path from 'path';
import multer from 'multer';
import { MeterReadingsService } from './meter-readings.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { TenantPortalService } from '@modules/tenant-portal/tenant-portal.service';
import { assertFeatureAllowed } from '@modules/tenant-portal/property-type-access';

const service = new MeterReadingsService();
const tenantPortal = new TenantPortalService();

const meterDir = path.join(__dirname, '../../../uploads/meter-readings');
fs.mkdirSync(meterDir, { recursive: true });

const meterStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, meterDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2)}${ext}`);
  },
});

export const uploadMeterImageMiddleware = multer({
  storage: meterStorage,
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image uploads are allowed'));
    }
    cb(null, true);
  },
}).single('meterImage');

const submitSchema = z.object({
  unitId: z.string().uuid().optional(),
  readingValue: z.coerce.number().positive(),
  billingCycle: z.string().optional(),
  ratePerUnit: z.coerce.number().positive().optional(),
  tenancyId: z.string().uuid().optional(),
});

export class MeterReadingsController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  submit = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = submitSchema.parse(req.body);
      if (!body.unitId) {
        return res.status(400).json({ error: 'unitId is required' });
      }
      const imageUrl = req.file
        ? `/uploads/meter-readings/${req.file.filename}`
        : null;
      const row = await service.submit({
        propertyId: req.params.propertyId,
        unitId: body.unitId,
        tenancyId: body.tenancyId,
        readingValue: body.readingValue,
        meterImageUrl: imageUrl,
        billingCycle: body.billingCycle,
        ratePerUnit: body.ratePerUnit,
        submittedBy: req.userId!,
        notifyOwners: false,
      });
      res.status(201).json({ data: row });
    } catch (err) {
      next(err);
    }
  };

  myReadings = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await tenantPortal.getMyTenancy(req.ctxId!);
      if (!tenancy) return res.status(404).json({ error: 'No active tenancy' });
      assertFeatureAllowed(tenancy, 'meter_reading');
      res.json({
        data: await service.listByUnit(String(tenancy.node_id)),
      });
    } catch (err) {
      next(err);
    }
  };

  submitMine = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await tenantPortal.getMyTenancy(req.ctxId!);
      if (!tenancy) return res.status(404).json({ error: 'No active tenancy' });
      assertFeatureAllowed(tenancy, 'meter_reading');
      const body = submitSchema.parse(req.body);
      const imageUrl = req.file
        ? `/uploads/meter-readings/${req.file.filename}`
        : null;
      const row = await service.submit({
        propertyId: String(tenancy.property_id),
        unitId: String(tenancy.node_id),
        tenancyId: String(tenancy.id),
        readingValue: body.readingValue,
        meterImageUrl: imageUrl,
        billingCycle: body.billingCycle,
        ratePerUnit: body.ratePerUnit,
        submittedBy: req.userId!,
        notifyOwners: true,
        notifyTenantUserId: null,
      });
      res.status(201).json({ data: row });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Could not submit reading';
      if (message.includes('cannot be less')) {
        return res.status(400).json({ error: message });
      }
      next(err);
    }
  };
}
