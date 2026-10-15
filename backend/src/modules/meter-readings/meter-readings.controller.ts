// modules/meter-readings/meter-readings.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import multer from 'multer';
import {
  MeterReadingsService,
  assertValidReadingValue,
  meterReadingForStaff,
} from './meter-readings.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { discardUpload, safeImageExtension, saveUpload } from '@shared/storage/file-storage';
import { assertFeatureAllowed } from '@modules/tenant-portal/property-type-access';
import {
  MeterAccessError,
  isTenantContext,
  resolveTenantMeterScope,
  type TenantMeterScope,
} from './meter-access';

const service = new MeterReadingsService();

export const uploadMeterImageMiddleware = multer({
  storage: multer.memoryStorage(),
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
  // Multipart sends strings; anything unparseable becomes NaN and is refused by
  // assertValidReadingValue with a stable code.
  readingValue: z
    .unknown()
    .transform((v) =>
      typeof v === 'number' ? v : typeof v === 'string' && v.trim() !== '' ? Number(v) : NaN,
    ),
  billingCycle: z.string().optional(),
  ratePerUnit: z.coerce.number().positive().optional(),
  tenancyId: z.string().uuid().optional(),
});

/**
 * Stores the meter photo only once the request has passed its checks, and
 * removes it again if the reading is rejected, so failures leave no file.
 */
async function withMeterImage<T>(
  req: AuthedRequest,
  submit: (meterImageUrl: string | null) => Promise<T>,
): Promise<T> {
  const imageUrl = req.file
    ? await saveUpload(
        'meter-readings',
        `${Date.now()}-${Math.random().toString(36).slice(2)}${safeImageExtension(req.file.originalname)}`,
        req.file,
      )
    : null;
  try {
    return await submit(imageUrl);
  } catch (err) {
    await discardUpload(imageUrl);
    throw err;
  }
}

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
  return withMeterImage(req, (meterImageUrl) =>
    service.submit({
      propertyId: scope.propertyId,
      unitId: scope.unitId,
      tenancyId: scope.tenancyId,
      readingValue: body.readingValue,
      meterImageUrl,
      billingCycle: body.billingCycle,
      submittedBy: req.userId!,
      notifyOwners: true,
    }),
  );
}

function parseSubmit(req: AuthedRequest) {
  const body = submitSchema.parse(req.body);
  assertValidReadingValue(body.readingValue);
  return body;
}

/** Staff never see the rate, the billed amount or invoice links. */
function forViewer(req: AuthedRequest, row: Record<string, unknown>) {
  return req.ctxRole === 'staff' ? meterReadingForStaff(row) : row;
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
      const rows = await service.listByProperty(req.params.propertyId);
      res.json({ data: rows.map((row: any) => forViewer(req, row)) });
    } catch (err) {
      next(err);
    }
  };

  submit = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = parseSubmit(req);
      if (isTenantContext(req)) {
        const scope = await tenantScopeFor(req, req.params.propertyId);
        return res.status(201).json({ data: await submitAsTenant(req, scope, body) });
      }
      // The rate is billing data: staff record readings at the property's own rate.
      if (req.ctxRole === 'staff' && body.ratePerUnit != null) {
        return res
          .status(403)
          .json({ error: 'Only owners, admins and managers can set the rate per unit.' });
      }
      if (!body.unitId) {
        return res.status(400).json({ error: 'unitId is required' });
      }
      const unitId = body.unitId;
      // The service verifies unitId / tenancyId belong to this property.
      const row = await withMeterImage(req, (meterImageUrl) =>
        service.submit({
          propertyId: req.params.propertyId,
          unitId,
          tenancyId: body.tenancyId,
          readingValue: body.readingValue,
          meterImageUrl,
          billingCycle: body.billingCycle,
          ratePerUnit: body.ratePerUnit,
          submittedBy: req.userId!,
          notifyOwners: false,
        }),
      );
      res.status(201).json({ data: forViewer(req, row) });
    } catch (err) {
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
        return res.status(404).json({ error: 'No active tenancy' });
      }
      const body = parseSubmit(req);
      res.status(201).json({ data: await submitAsTenant(req, scope, body) });
    } catch (err) {
      next(err);
    }
  };
}
