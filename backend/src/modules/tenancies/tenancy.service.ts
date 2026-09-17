// modules/tenancies/tenancy.service.ts
//
// Attaches a real tenant to a specific hierarchy_node. If the tenant's phone
// doesn't have a Dormly account yet, one is created here (unverified) —
// when they eventually log in with OTP using that same phone, our
// ContextService will find this tenancy and offer it as a login context.

import { query } from '@config/db';
import { ensureNotificationsSchema } from '@modules/notifications/move-out-notifications';

interface CreateTenancyInput {
  propertyId: string;
  nodeId: string;
  phone: string;
  fullName: string;
  email?: string;
  address?: string;
  companyName?: string;
  aadhaarNumber?: string;
  moveInAt?: string;
  securityDeposit?: number;
  notes?: string;
}

interface UpdateTenancyInput {
  fullName?: string;
  email?: string;
  address?: string;
  companyName?: string;
  aadhaarNumber?: string;
  moveInAt?: string;
  moveOutAt?: string;
  monthlyRent?: number;
  securityDeposit?: number;
  notes?: string;
  status?: 'active' | 'ended' | 'pending';
  occupation?: string;
  emergencyContactName?: string;
  emergencyContactRelation?: string;
  emergencyContactPhone?: string;
  idType?: string;
  policeVerificationDone?: boolean;
  kycStatus?: 'pending' | 'submitted' | 'verified' | 'rejected';
}

export class TenancyService {
  async listByNode(nodeId: string) {
    return query(
      `SELECT t.*, u.phone, u.name AS user_name
       FROM tenancies t
       JOIN users u ON u.id = t.user_id
       WHERE t.node_id = $1
       ORDER BY t.created_at DESC`,
      [nodeId],
    );
  }

  async listByProperty(propertyId: string) {
    return query(
      `SELECT t.*, u.phone, u.name AS user_name, n.name AS node_name,
              l.display_name AS level_name,
              floor_node.name AS floor_name,
              EXISTS (
                SELECT 1 FROM invoices i
                WHERE i.tenancy_id = t.id
                  AND i.status IN ('pending', 'overdue', 'partial')
              ) AS has_due
       FROM tenancies t
       JOIN users u ON u.id = t.user_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       JOIN hierarchy_levels l ON l.id = n.level_id
       LEFT JOIN LATERAL (
         WITH RECURSIVE ancestors AS (
           SELECT hn.id, hn.name, hn.parent_node_id, hn.level_id
           FROM hierarchy_nodes hn
           WHERE hn.id = n.id
           UNION ALL
           SELECT p.id, p.name, p.parent_node_id, p.level_id
           FROM hierarchy_nodes p
           INNER JOIN ancestors a ON p.id = a.parent_node_id
         )
         SELECT a.name
         FROM ancestors a
         JOIN hierarchy_levels hl ON hl.id = a.level_id
         WHERE lower(hl.display_name) LIKE '%floor%'
         LIMIT 1
       ) floor_node ON true
       WHERE t.property_id = $1
       ORDER BY t.full_name ASC NULLS LAST, t.created_at DESC`,
      [propertyId],
    );
  }

  async getById(tenancyId: string) {
    const rows = await query(
      `SELECT t.*, u.phone, u.name AS user_name, n.name AS node_name
       FROM tenancies t
       JOIN users u ON u.id = t.user_id
       LEFT JOIN hierarchy_nodes n ON n.id = t.node_id
       WHERE t.id = $1`,
      [tenancyId],
    );
    return rows[0] ?? null;
  }

  private normalizeUpdateInput(input: UpdateTenancyInput & Record<string, unknown>): UpdateTenancyInput {
    return {
      fullName: input.fullName,
      email: input.email,
      address: input.address,
      companyName: input.companyName,
      aadhaarNumber: input.aadhaarNumber,
      moveInAt: input.moveInAt,
      moveOutAt: input.moveOutAt,
      notes: input.notes,
      status: input.status,
      monthlyRent: input.monthlyRent ?? (input.monthly_rent as number | undefined),
      securityDeposit: input.securityDeposit ?? (input.security_deposit as number | undefined),
      occupation: input.occupation as string | undefined,
      emergencyContactName:
          input.emergencyContactName ?? (input.emergency_contact_name as string | undefined),
      emergencyContactRelation:
          input.emergencyContactRelation ?? (input.emergency_contact_relation as string | undefined),
      emergencyContactPhone:
          input.emergencyContactPhone ?? (input.emergency_contact_phone as string | undefined),
      idType: input.idType ?? (input.id_type as string | undefined),
      policeVerificationDone:
          input.policeVerificationDone ?? (input.police_verification_done as boolean | undefined),
      kycStatus: input.kycStatus ?? (input.kyc_status as UpdateTenancyInput['kycStatus']),
    };
  }

  async listDocuments(tenancyId: string) {
    return query(
      `SELECT * FROM tenant_documents WHERE tenancy_id = $1 ORDER BY uploaded_at DESC`,
      [tenancyId],
    );
  }

  async create(input: CreateTenancyInput) {
    await this.assertNodeAssignable(input.propertyId, input.nodeId);

    let user = (await query<{ id: string }>(`SELECT id FROM users WHERE phone = $1`, [input.phone]))[0];
    if (!user) {
      user = (await query<{ id: string }>(
        `INSERT INTO users (phone, name) VALUES ($1, $2) RETURNING id`,
        [input.phone, input.fullName],
      ))[0];
    }

    const [tenancy] = await query(
      `INSERT INTO tenancies
        (user_id, property_id, node_id, full_name, email, address, company_name,
         aadhaar_number, move_in_at, security_deposit, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       RETURNING *`,
      [
        user.id, input.propertyId, input.nodeId, input.fullName, input.email ?? null,
        input.address ?? null, input.companyName ?? null, input.aadhaarNumber ?? null,
        input.moveInAt ?? null, input.securityDeposit ?? null, input.notes ?? null,
      ],
    );
    return tenancy;
  }

  /** Ensures the node exists, belongs to the property, is a rentable unit, and is vacant. */
  private async assertNodeAssignable(propertyId: string, nodeId: string): Promise<void> {
    const rows = await query<{
      property_id: string;
      level_id: string;
      level_name: string;
      supports_occupancy: boolean;
    }>(
      `SELECT n.property_id, n.level_id, l.display_name AS level_name, l.supports_occupancy
       FROM hierarchy_nodes n
       JOIN hierarchy_levels l ON l.id = n.level_id
       WHERE n.id = $1`,
      [nodeId],
    );
    const node = rows[0];
    if (!node || node.property_id !== propertyId) {
      throw new Error('The selected unit was not found in this property.');
    }

    if (!node.supports_occupancy) {
      const deeper = await query<{ display_name: string }>(
        `WITH RECURSIVE descendants AS (
           SELECT id, supports_occupancy, display_name, parent_level_id
           FROM hierarchy_levels WHERE parent_level_id = $1
           UNION ALL
           SELECT hl.id, hl.supports_occupancy, hl.display_name, hl.parent_level_id
           FROM hierarchy_levels hl
           JOIN descendants d ON hl.parent_level_id = d.id
         )
         SELECT display_name FROM descendants WHERE supports_occupancy = true LIMIT 1`,
        [node.level_id],
      );
      if (deeper[0]) {
        throw new Error(
          `Assign the tenant to a specific ${deeper[0].display_name}, not the ${node.level_name}.`,
        );
      }
    }

    const occupied = await query<{ id: string }>(
      `SELECT id FROM tenancies WHERE node_id = $1 AND status = 'active' LIMIT 1`,
      [nodeId],
    );
    if (occupied[0]) {
      throw new Error('This unit already has an active tenant. End the current tenancy first.');
    }
  }

  async update(tenancyId: string, input: UpdateTenancyInput & Record<string, unknown>) {
    const payload = this.normalizeUpdateInput(input);
    const columnMap: Record<string, string> = {
      fullName: 'full_name', email: 'email', address: 'address', companyName: 'company_name',
      aadhaarNumber: 'aadhaar_number', moveInAt: 'move_in_at', moveOutAt: 'move_out_at',
      monthlyRent: 'monthly_rent', securityDeposit: 'security_deposit', notes: 'notes', status: 'status',
      occupation: 'occupation',
      emergencyContactName: 'emergency_contact_name',
      emergencyContactRelation: 'emergency_contact_relation',
      emergencyContactPhone: 'emergency_contact_phone',
      idType: 'id_type',
      policeVerificationDone: 'police_verification_done',
      kycStatus: 'kyc_status',
    };
    const fields: string[] = [];
    const values: any[] = [];
    let i = 1;
    for (const [key, column] of Object.entries(columnMap)) {
      const value = (payload as any)[key];
      if (value !== undefined) {
        fields.push(`${column} = $${i++}`);
        values.push(value);
      }
    }
    if (fields.length === 0) {
      throw new Error('No valid fields to update.');
    }
    fields.push('updated_at = now()');
    values.push(tenancyId);
    const updated = await query(
      `UPDATE tenancies SET ${fields.join(', ')} WHERE id = $${i} RETURNING id`,
      values,
    );
    if (!updated[0]) {
      throw new Error('Tenancy not found.');
    }
    const tenancy = await this.getById(tenancyId);
    if (!tenancy) {
      throw new Error('Tenancy not found after update.');
    }
    return tenancy;
  }

  async endTenancy(tenancyId: string) {
    return this.update(tenancyId, { status: 'ended', moveOutAt: new Date().toISOString() });
  }

  /**
   * Owner reviews a tenant move-out request.
   * Never overwrites notice_given_at (immutable audit timestamp).
   */
  async reviewMoveOutRequest(
    tenancyId: string,
    input: {
      action: 'approve' | 'modify' | 'reject';
      proposedExitDate?: string;
      waiveNoticePenalty?: boolean;
    },
  ) {
    const existing = await this.getById(tenancyId);
    if (!existing) throw new Error('Tenancy not found.');
    if (!existing.move_out_request_status && !existing.notice_given_at) {
      throw new Error('No move-out request on file for this tenancy.');
    }

    if (input.action === 'reject') {
      await query(
        `UPDATE tenancies SET
           move_out_request_status = 'rejected',
           updated_at = now()
         WHERE id = $1`,
        [tenancyId],
      );
      return this.getById(tenancyId);
    }

    let proposedIso: string | null = null;
    if (input.action === 'modify') {
      if (!input.proposedExitDate) {
        throw new Error('proposedExitDate is required when modifying.');
      }
      const proposed = new Date(input.proposedExitDate);
      if (Number.isNaN(proposed.getTime())) throw new Error('Invalid proposed exit date.');
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const day = new Date(proposed);
      day.setHours(0, 0, 0, 0);
      if (day < today) {
        throw new Error('Modified exit date cannot be in the past.');
      }
      proposedIso = day.toISOString();
    }

    const status =
      input.action === 'approve' ? 'approved' : 'modified_by_mutual_agreement';

    await query(
      `UPDATE tenancies SET
         move_out_request_status = $2::move_out_request_status,
         planned_move_out_at = COALESCE($3::timestamptz, planned_move_out_at),
         move_out_waive_notice_penalty = COALESCE($4, move_out_waive_notice_penalty),
         updated_at = now()
       WHERE id = $1`,
      [
        tenancyId,
        status,
        proposedIso,
        input.waiveNoticePenalty === undefined ? null : input.waiveNoticePenalty,
      ],
    );

    const updated = await this.getById(tenancyId);
    if (updated && (input.action === 'approve' || input.action === 'modify')) {
      await this.notifyTenantOfMoveOutDecision(updated, input.action).catch(
        (err) =>
          console.warn('[tenancies] tenant move-out notification failed:', err),
      );
    }
    return updated;
  }

  /** Notify the tenant user that their move-out date was approved/modified. */
  private async notifyTenantOfMoveOutDecision(
    tenancy: any,
    action: 'approve' | 'modify',
  ) {
    const tenantUserId = tenancy.user_id ?? tenancy.userId;
    const propertyId = tenancy.property_id ?? tenancy.propertyId;
    const tenancyId = tenancy.id;
    if (!tenantUserId || !tenancyId) return;

    const exitRaw = tenancy.planned_move_out_at ?? tenancy.plannedMoveOutAt;
    const exitDate = exitRaw ? new Date(exitRaw) : null;
    const exitLabel =
      exitDate && !Number.isNaN(exitDate.getTime())
        ? exitDate.toLocaleDateString('en-IN', {
            day: 'numeric',
            month: 'short',
            year: 'numeric',
          })
        : 'the agreed date';

    const title =
      action === 'modify'
        ? 'Move-Out Date Updated'
        : 'Move-Out Notice Approved';
    const body =
      action === 'modify'
        ? `Owner updated your move-out date to ${exitLabel}.`
        : `Owner has confirmed your move-out date for ${exitLabel}.`;
    const payload = JSON.stringify({
      tenancy_id: String(tenancyId),
      tenancyId: String(tenancyId),
      property_id: propertyId ? String(propertyId) : null,
      propertyId: propertyId ? String(propertyId) : null,
      route: '/tenant-home',
      action,
    });

    await ensureNotificationsSchema().catch(() => false);

    try {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body, data)
         VALUES ($1, $2, 'move_out_approved', $3, $4, $5::jsonb)`,
        [tenantUserId, propertyId ?? null, title, body, payload],
      );
      console.log(
        `>>> INSERTING NOTIFICATION FOR USER: ${tenantUserId} <<< type=move_out_approved`,
      );
    } catch (err) {
      console.error('>>> tenant move_out_approved insert failed <<<', err);
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body)
         VALUES ($1, $2, 'move_out_approved', $3, $4)`,
        [tenantUserId, propertyId ?? null, title, body],
      );
    }
  }

  async setAgreementUrl(tenancyId: string, url: string) {
    const [tenancy] = await query(
      `UPDATE tenancies SET agreement_pdf_url = $1, updated_at = now() WHERE id = $2 RETURNING *`,
      [url, tenancyId],
    );
    return tenancy;
  }

  async setProfilePhotoUrl(tenancyId: string, url: string) {
    const [tenancy] = await query(
      `UPDATE tenancies SET profile_photo_url = $1, updated_at = now() WHERE id = $2 RETURNING *`,
      [url, tenancyId],
    );
    if (!tenancy) throw new Error('Tenancy not found.');
    return tenancy;
  }

  async upsertDocument(tenancyId: string, docType: string, fileUrl: string) {
    const rows = await query(
      `INSERT INTO tenant_documents (tenancy_id, doc_type, file_url, status)
       VALUES ($1, $2::tenant_document_type, $3, 'submitted')
       ON CONFLICT (tenancy_id, doc_type)
       DO UPDATE SET file_url = EXCLUDED.file_url, status = 'submitted', uploaded_at = now()
       RETURNING *`,
      [tenancyId, docType, fileUrl],
    );
    return rows[0];
  }
}