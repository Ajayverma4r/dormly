// modules/tenancies/tenancy.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { TenancyService } from './tenancy.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import multer from 'multer';
import path from 'path';
import fs from 'fs';

const uploadDir = path.join(__dirname, '../../../uploads/agreements');
const profilePhotoDir = path.join(__dirname, '../../../uploads/tenant-photos');
const tenantDocDir = path.join(__dirname, '../../../uploads/tenant-documents');
fs.mkdirSync(uploadDir, { recursive: true });
fs.mkdirSync(profilePhotoDir, { recursive: true });
fs.mkdirSync(tenantDocDir, { recursive: true });

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

const profilePhotoStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, profilePhotoDir),
  filename: (req, _file, cb) =>
    cb(null, `${req.params.tenancyId}-photo-${Date.now()}.jpg`),
});

export const uploadProfilePhotoMiddleware = multer({
  storage: profilePhotoStorage,
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image uploads are allowed'));
    }
    cb(null, true);
  },
  limits: { fileSize: 150 * 1024 }, // 150KB server cap (client targets 100KB)
}).single('photo');

const tenantDocStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, tenantDocDir),
  filename: (req, _file, cb) =>
    cb(null, `${req.params.tenancyId}-doc-${Date.now()}.jpg`),
});

export const uploadTenantDocumentMiddleware = multer({
  storage: tenantDocStorage,
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

  getById = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.getById(req.params.tenancyId);
      if (!tenancy) return res.status(404).json({ error: 'Tenancy not found' });
      res.json({ data: tenancy });
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
      const url = `/uploads/agreements/${req.file.filename}`;
      const tenancy = await service.setAgreementUrl(req.params.tenancyId, url);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  uploadProfilePhoto = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'No photo uploaded' });
      const url = `/uploads/tenant-photos/${req.file.filename}`;
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
      const url = `/uploads/tenant-documents/${req.file.filename}`;
      const doc = await service.upsertDocument(req.params.tenancyId, docType, url);
      res.json({ data: doc });
    } catch (err) { next(err); }
  };

  endTenancy = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.endTenancy(req.params.tenancyId);
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };
}