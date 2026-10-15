// modules/tenancies/tenancy.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { TenancyService } from './tenancy.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import multer from 'multer';
import { readUpload, keyFromUploadUrl, saveUpload } from '@shared/storage/file-storage';

export const uploadAgreementMiddleware = multer({
  storage: multer.memoryStorage(),
  fileFilter: (_req, file, cb) => {
    if (file.mimetype !== 'application/pdf') {
      return cb(new Error('Only PDF files are allowed'));
    }
    cb(null, true);
  },
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
}).single('agreement');

export const uploadProfilePhotoMiddleware = multer({
  storage: multer.memoryStorage(),
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image uploads are allowed'));
    }
    cb(null, true);
  },
  limits: { fileSize: 150 * 1024 }, // 150KB server cap (client targets 100KB)
}).single('photo');

export const uploadTenantDocumentMiddleware = multer({
  storage: multer.memoryStorage(),
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image uploads are allowed'));
    }
    cb(null, true);
  },
  limits: { fileSize: 150 * 1024 },
}).single('document');

const service = new TenancyService();

const createSchema = z.object({
  nodeId: z.string().uuid().optional(),
  unitName: z.string().min(1).optional(),
  portionName: z.string().min(1).optional(), // alias for unitName
  phone: z.string().min(6),
  fullName: z.string().min(1),
  email: z.string().email().optional(),
  address: z.string().optional(),
  companyName: z.string().optional(),
  aadhaarNumber: z.string().optional(),
  moveInAt: z.string().optional(),
  securityDeposit: z.number().optional(),
  notes: z.string().optional(),
  monthlyRent: z.number().min(0).optional(),
  monthly_rent: z.number().min(0).optional(),
  includePastRentArrears: z.boolean().optional(),
  include_past_rent_arrears: z.boolean().optional(),
}).superRefine((data, ctx) => {
  const hasNode = Boolean(data.nodeId);
  const hasUnit = Boolean(
    (data.unitName && data.unitName.trim()) ||
      (data.portionName && data.portionName.trim()),
  );
  if (!hasNode && !hasUnit) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'Provide nodeId or unitName (property portion / unit).',
      path: ['unitName'],
    });
  }
}).transform((data) => ({
  nodeId: data.nodeId,
  unitName: data.unitName?.trim() || data.portionName?.trim() || undefined,
  phone: data.phone,
  fullName: data.fullName,
  email: data.email,
  address: data.address,
  companyName: data.companyName,
  aadhaarNumber: data.aadhaarNumber,
  moveInAt: data.moveInAt,
  securityDeposit: data.securityDeposit,
  notes: data.notes,
  monthlyRent: data.monthlyRent ?? data.monthly_rent,
  includePastRentArrears:
    data.includePastRentArrears ?? data.include_past_rent_arrears,
}));

const updateSchema = z
  .object({
    fullName: z.string().min(1).optional(),
    email: z.string().optional(),
    address: z.string().optional(),
    companyName: z.string().optional(),
    aadhaarNumber: z.string().optional(),
    moveInAt: z.string().optional(),
    moveOutAt: z.string().optional(),
    monthlyRent: z.number().min(0).optional(),
    monthly_rent: z.number().min(0).optional(),
    securityDeposit: z.number().min(0).optional(),
    security_deposit: z.number().min(0).optional(),
    notes: z.string().optional(),
    status: z.enum(['active', 'ended', 'pending']).optional(),
    occupation: z.string().optional(),
    emergencyContactName: z.string().optional(),
    emergency_contact_name: z.string().optional(),
    emergencyContactRelation: z.string().optional(),
    emergency_contact_relation: z.string().optional(),
    emergencyContactPhone: z.string().optional(),
    emergency_contact_phone: z.string().optional(),
    idType: z.string().optional(),
    id_type: z.string().optional(),
    policeVerificationDone: z.boolean().optional(),
    police_verification_done: z.boolean().optional(),
    kycStatus: z.enum(['pending', 'submitted', 'verified', 'rejected']).optional(),
    kyc_status: z.enum(['pending', 'submitted', 'verified', 'rejected']).optional(),
  })
  .transform((data) => ({
    fullName: data.fullName,
    email: data.email?.trim() === '' ? undefined : data.email,
    address: data.address,
    companyName: data.companyName,
    aadhaarNumber: data.aadhaarNumber,
    moveInAt: data.moveInAt,
    moveOutAt: data.moveOutAt,
    notes: data.notes,
    status: data.status,
    monthlyRent: data.monthlyRent ?? data.monthly_rent,
    securityDeposit: data.securityDeposit ?? data.security_deposit,
    occupation: data.occupation,
    emergencyContactName: data.emergencyContactName ?? data.emergency_contact_name,
    emergencyContactRelation: data.emergencyContactRelation ?? data.emergency_contact_relation,
    emergencyContactPhone: data.emergencyContactPhone ?? data.emergency_contact_phone,
    idType: data.idType ?? data.id_type,
    policeVerificationDone: data.policeVerificationDone ?? data.police_verification_done,
    kycStatus: data.kycStatus ?? data.kyc_status,
  }));

/** Contact, KYC and rent/dues fields staff do not need for day-to-day operations. */
export const STAFF_HIDDEN_TENANCY_FIELDS = [
  'phone', 'emergency_contact_phone',
  'aadhaar_number', 'id_type', 'agreement_pdf_url',
  'monthly_rent', 'security_deposit',
  'has_due', 'earliest_open_due_date', 'has_overdue', 'has_draft', 'has_sent_invoice',
] as const;

function forViewer<T extends Record<string, unknown>>(req: AuthedRequest, row: T): T {
  if (req.ctxRole !== 'staff') return row;
  const copy: Record<string, unknown> = { ...row };
  for (const key of STAFF_HIDDEN_TENANCY_FIELDS) delete copy[key];
  return copy as T;
}

export class TenancyController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const data = req.query.nodeId
        ? await service.listByNode(req.params.propertyId, req.query.nodeId as string)
        : await service.listByProperty(req.params.propertyId);
      res.json({ data: data.map((row: any) => forViewer(req, row)) });
    } catch (err) { next(err); }
  };

  create = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createSchema.parse(req.body);
      const tenancy = await service.create({ propertyId: req.params.propertyId, ...body });
      res.status(201).json({ data: tenancy });
    } catch (err) { next(err); }
  };

  getById = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.getById(req.params.tenancyId);
      if (!tenancy) return res.status(404).json({ error: 'Tenancy not found' });
      res.json({ data: forViewer(req, tenancy) });
    } catch (err) { next(err); }
  };

  listDocuments = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const data = await service.listDocuments(req.params.tenancyId);
      res.json({ data });
    } catch (err) { next(err); }
  };

  update = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = updateSchema.parse(req.body);
      const tenancy = await service.update(req.params.tenancyId, body);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  uploadAgreement = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
      const url = await saveUpload(
        'agreements', `${req.params.tenancyId}-${Date.now()}.pdf`, req.file);
      const tenancy = await service.setAgreementUrl(req.params.tenancyId, url);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  uploadProfilePhoto = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'No photo uploaded' });
      const url = await saveUpload(
        'tenant-photos', `${req.params.tenancyId}-photo-${Date.now()}.jpg`, req.file);
      const tenancy = await service.setProfilePhotoUrl(req.params.tenancyId, url);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  uploadDocument = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'No document uploaded' });
      const docType = (req.body.docType ?? req.body.doc_type ?? 'aadhaar') as string;
      const allowed = ['aadhaar', 'pan', 'photo', 'agreement', 'address_proof', 'other'];
      if (!allowed.includes(docType)) {
        return res.status(400).json({ error: 'Invalid document type' });
      }
      const url = await saveUpload(
        'tenant-documents', `${req.params.tenancyId}-doc-${Date.now()}.jpg`, req.file);
      const doc = await service.upsertDocument(req.params.tenancyId, docType, url);
      res.json({ data: doc });
    } catch (err) { next(err); }
  };

  documentFile = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const doc = await service.getDocument(req.params.tenancyId, req.params.documentId);
      const key = keyFromUploadUrl(doc?.file_url);
      const stored = key ? await readUpload(key) : null;
      if (!stored) return res.status(404).json({ error: 'Document not found' });
      res.setHeader('Content-Type', stored.contentType);
      res.setHeader('Cache-Control', 'private, no-store');
      res.send(stored.body);
    } catch (err) { next(err); }
  };

  endTenancy = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.endTenancy(req.params.tenancyId);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  reviewMoveOutRequest = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = z.object({
        action: z.enum(['approve', 'modify', 'reject']),
        proposedExitDate: z.string().optional(),
        waiveNoticePenalty: z.boolean().optional(),
      }).parse(req.body);
      const tenancy = await service.reviewMoveOutRequest(req.params.tenancyId, body);
      res.json({ data: tenancy });
    } catch (err) {
      if (err instanceof z.ZodError) {
        return res.status(400).json({ error: err.errors[0]?.message ?? 'Invalid request' });
      }
      const message = err instanceof Error ? err.message : 'Review failed';
      if (message.includes('past') || message.includes('No move-out') || message.includes('not found')) {
        return res.status(400).json({ error: message });
      }
      next(err);
    }
  };
}