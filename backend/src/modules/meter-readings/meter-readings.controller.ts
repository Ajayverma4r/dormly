// modules/meter-readings/meter-readings.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import fs from 'fs';
import path from 'path';
import multer from 'multer';
import { MeterReadingsService } from './meter-readings.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { assertFeatureAllowed } from '@modules/tenant-portal/property-type-access';
import {
  MeterAccessError,
  isTenantContext,
  resolveTenantMeterScope,
  type TenantMeterScope,
} from './meter-access';

const service = new MeterReadingsService();

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

/** Drops an upload that will not be stored, so rejected requests leave no file. */
function discardUpload(req: AuthedRequest) {
  if (req.file?.path) fs.unlink(req.file.path, () => undefined);
}

const imageUrlOf = (req: AuthedRequest) =>
  req.file ? `/uploads/meter-readings/${req.file.filename}` : null;

/**
 * Tenant submit: unit and tenancy come from the caller's own active tenancy.
 * A client-supplied unit or tenancy must match it; the rate is the owner's.
 */
async function submitAsTenant(
  req: AuthedRequest,
  scope: TenantMeterScope,
  body: z.infer<typeof submitSchema>,
) {
  if (
    (body.unitId != null && body.unitId !== scope.unitId) ||
    (body.tenancyId != null && body.tenancyId !== scope.tenancyId)
  ) {
    throw new MeterAccessError();
  }
  assertFeatureAllowed(scope, 'meter_reading');
  return service.submit({
    propertyId: scope.propertyId,
    unitId: scope.unitId,
    tenancyId: scope.tenancyId,
    readingValue: body.readingValue,
    meterImageUrl: imageUrlOf(req),
    billingCycle: body.billingCycle,
    submittedBy: req.userId!,
    notifyOwners: true,
  });
}

/** Tenant scope for a property route; MeterAccessError if it is not theirs. */
async function tenantScopeFor(req: AuthedRequest, propertyId: string) {
  const scope = await resolveTenantMeterScope(req);
  if (!scope || scope.propertyId !== propertyId) throw new MeterAccessError();
  return scope;
}

export class MeterReadingsController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (isTenantContext(req)) {
        const scope = await tenantScopeFor(req, req.params.propertyId);
        assertFeatureAllowed(scope, 'meter_reading');
        return res.json({ data: await service.listForTenancy(scope) });
      }
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  submit = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = submitSchema.parse(req.body);
      if (isTenantContext(req)) {
        const scope = await tenantScopeFor(req, req.params.propertyId);
        return res.status(201).json({ data: await submitAsTenant(req, scope, body) });
      }
      if (!body.unitId) {
        discardUpload(req);
        return res.status(400).json({ error: 'unitId is required' });
      }
      // The service verifies unitId / tenancyId belong to this property.
      const row = await service.submit({
        propertyId: req.params.propertyId,
        unitId: body.unitId,
        tenancyId: body.tenancyId,
        readingValue: body.readingValue,
        meterImageUrl: imageUrlOf(req),
        billingCycle: body.billingCycle,
        ratePerUnit: body.ratePerUnit,
        submittedBy: req.userId!,
        notifyOwners: false,
      });
      res.status(201).json({ data: row });
    } catch (err) {
      discardUpload(req);
      next(err);
    }
  };

  myReadings = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const scope = await resolveTenantMeterScope(req);
      if (!scope) return res.status(404).json({ error: 'No active tenancy' });
      assertFeatureAllowed(scope, 'meter_reading');
      res.json({ data: await service.listForTenancy(scope) });
    } catch (err) {
      next(err);
    }
  };

  submitMine = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const scope = await resolveTenantMeterScope(req);
      if (!scope) {
        discardUpload(req);
        return res.status(404).json({ error: 'No active tenancy' });
      }
      const body = submitSchema.parse(req.body);
      res.status(201).json({ data: await submitAsTenant(req, scope, body) });
    } catch (err) {
      discardUpload(req);
      const message = err instanceof Error ? err.message : 'Could not submit reading';
      if (message.includes('cannot be less')) {
        return res.status(400).json({ error: message });
      }
      next(err);
    }
  };
}
