// modules/complaints/complaint.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import multer from 'multer';
import {
  ComplaintService,
  complaintSchemaCaps,
  type CommentAudience,
} from './complaint.service';
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

const PROPERTY_TEAM_ROLES = new Set(['owner', 'admin', 'manager', 'staff']);
const NO_COMPLAINT_ACCESS = { error: 'You do not have access to these complaints.' };
const OWN_UNIT_ONLY = { error: 'You can only raise complaints for your own unit.' };

/** The caller's active tenancy placement, re-read from the database rather than trusted from the request. */
async function verifiedTenantPlacement(req: AuthedRequest) {
  if (req.ctxType !== 'tenancy' || req.ctxRole !== 'tenant' || !req.ctxId || !req.userId) {
    return null;
  }
  const placement = await service.tenantPlacement(req.ctxId, req.userId);
  if (!placement || placement.propertyId !== req.ctxPropertyId) return null;
  return placement;
}

const NOT_AVAILABLE = { error: 'This feature is not available yet.' };

const commentSchema = z.object({
  body: z.string().trim().min(1, 'Comment cannot be empty').max(2000),
  visibility: z.enum(['internal', 'tenant_visible']).optional(),
});

const assignSchema = z.object({
  assigneeUserId: z.string().uuid().nullable(),
});

/**
 * 'team' for the property team; 'tenant' only for the tenant who raised this
 * complaint, through a verified active tenancy at this property.
 */
async function commentAudience(req: AuthedRequest): Promise<CommentAudience | null> {
  if (PROPERTY_TEAM_ROLES.has(req.ctxRole ?? '')) return 'team';
  const placement = await verifiedTenantPlacement(req);
  if (!placement || placement.propertyId !== req.params.propertyId) return null;
  const raisedBy = await service.raisedBy(req.params.propertyId, req.params.complaintId);
  return raisedBy && raisedBy === req.userId ? 'tenant' : null;
}

/**
 * Once assignment exists, staff see complaints assigned to them or to nobody,
 * and the reporter's phone number only on their own. Before 027 nothing is
 * assigned, so staff keep the property-wide list.
 */
async function forStaffViewer(req: AuthedRequest, rows: any[]) {
  if (req.ctxRole !== 'staff' || !(await complaintSchemaCaps()).assignment) return rows;
  return rows
    .filter((r) => r.assigned_to == null || String(r.assigned_to) === req.userId)
    .map((r) => {
      if (String(r.assigned_to) === req.userId) return r;
      const { raised_by_phone: _phone, ...rest } = r;
      return rest;
    });
}

/** Staff may not open a complaint assigned to someone else (after 027). */
async function staffHiddenComplaint(req: AuthedRequest) {
  if (req.ctxRole !== 'staff' || !(await complaintSchemaCaps()).assignment) return false;
  const assignee = await service.assigneeOf(req.params.propertyId, req.params.complaintId);
  return assignee != null && assignee !== req.userId;
}

export class ComplaintController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const propertyId = req.params.propertyId;
      if (PROPERTY_TEAM_ROLES.has(req.ctxRole ?? '')) {
        return res.json({
          data: await forStaffViewer(req, await service.listByProperty(propertyId)),
        });
      }
      const placement = await verifiedTenantPlacement(req);
      if (!placement || placement.propertyId !== propertyId) {
        return res.status(403).json(NO_COMPLAINT_ACCESS);
      }
      res.json({ data: await service.listForTenant(propertyId, req.userId!) });
    } catch (err) {
      next(err);
    }
  };

  create = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const propertyId = req.params.propertyId;
      const body = createSchema.parse({
        ...req.body,
        photoUrls: req.body.photoUrls
          ? typeof req.body.photoUrls === 'string'
            ? JSON.parse(req.body.photoUrls)
            : req.body.photoUrls
          : undefined,
      });
      if (PROPERTY_TEAM_ROLES.has(req.ctxRole ?? '')) {
        if (!(await service.nodeInProperty(body.nodeId, propertyId))) {
          return res.status(400).json({ error: 'Unit does not belong to this property.' });
        }
      } else {
        const placement = await verifiedTenantPlacement(req);
        if (!placement || placement.propertyId !== propertyId || placement.nodeId !== body.nodeId) {
          return res.status(403).json(OWN_UNIT_ONLY);
        }
      }
      const photoUrls = [...(body.photoUrls ?? []), ...(await filesToUrls(req))];
      const complaint = await service.create(
        propertyId,
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
      // Before migration 027 there is no assignment, so staff keep property-wide updates.
      if (
        req.ctxRole === 'staff' &&
        (await complaintSchemaCaps()).assignment &&
        !(await service.isAssignedTo(req.params.propertyId, req.params.complaintId, req.userId!))
      ) {
        return res
          .status(403)
          .json({ error: 'Staff can only update complaints assigned to them.' });
      }
      const complaint = await service.updateStatus(
        req.params.propertyId,
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
          // Optional echo of the tenancy's placement; the server's own lookup is authoritative.
          propertyId: z.string().uuid().optional(),
          nodeId: z.string().uuid().optional(),
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
      const placement = await verifiedTenantPlacement(req);
      if (
        !placement ||
        (body.propertyId && body.propertyId !== placement.propertyId) ||
        (body.nodeId && body.nodeId !== placement.nodeId)
      ) {
        return res.status(403).json(OWN_UNIT_ONLY);
      }
      const photoUrls = [...(body.photoUrls ?? []), ...(await filesToUrls(req))];
      const complaint = await service.create(
        placement.propertyId,
        placement.nodeId,
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

  listComments = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!(await complaintSchemaCaps()).comments) return res.status(503).json(NOT_AVAILABLE);
      const audience = await commentAudience(req);
      if (!audience || (await staffHiddenComplaint(req))) {
        return res.status(403).json(NO_COMPLAINT_ACCESS);
      }
      res.json({
        data: await service.listComments(req.params.propertyId, req.params.complaintId, audience),
      });
    } catch (err) {
      next(err);
    }
  };

  addComment = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!(await complaintSchemaCaps()).comments) return res.status(503).json(NOT_AVAILABLE);
      const audience = await commentAudience(req);
      if (!audience) return res.status(403).json(NO_COMPLAINT_ACCESS);
      const body = commentSchema.parse(req.body);
      const { propertyId, complaintId } = req.params;
      if (
        req.ctxRole === 'staff' &&
        !(await service.isAssignedTo(propertyId, complaintId, req.userId!))
      ) {
        return res
          .status(403)
          .json({ error: 'Staff can only comment on complaints assigned to them.' });
      }
      // Tenant comments are always visible to the tenant; team notes stay internal unless shared.
      const visibility =
        audience === 'tenant' ? 'tenant_visible' : (body.visibility ?? 'internal');
      const id = await service.addComment(
        propertyId,
        complaintId,
        { userId: req.userId!, role: req.ctxRole! },
        body.body,
        visibility,
      );
      if (!id) return res.status(404).json({ error: 'Complaint not found' });
      const all = await service.listComments(propertyId, complaintId, audience);
      res.status(201).json({ data: all.find((c: any) => String(c.id) === id) });
    } catch (err) {
      next(err);
    }
  };

  assignees = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (!(await complaintSchemaCaps()).assignment) return res.status(503).json(NOT_AVAILABLE);
      res.json({ data: await service.listAssignees(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  assign = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const caps = await complaintSchemaCaps();
      if (!caps.assignment || !caps.comments) return res.status(503).json(NOT_AVAILABLE);
      const { assigneeUserId } = assignSchema.parse(req.body);
      const { propertyId, complaintId } = req.params;
      const result = await service.assign(propertyId, complaintId, assigneeUserId, {
        userId: req.userId!,
        role: req.ctxRole!,
      });
      if (result === 'ineligible') {
        return res
          .status(422)
          .json({ error: 'That person is not an eligible team member for this property.' });
      }
      const [complaint] = await service.listByProperty(propertyId, complaintId);
      if (!complaint) return res.status(404).json({ error: 'Complaint not found' });
      if (result === 'assigned' && String(complaint.assigned_to) !== req.userId) {
        await service.notifyAssignee(propertyId, complaint);
      }
      res.json({ data: complaint });
    } catch (err) {
      next(err);
    }
  };
}
