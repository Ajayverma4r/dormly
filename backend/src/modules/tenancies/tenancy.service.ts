// modules/tenancies/tenancy.service.ts
//
// Attaches a real tenant to a specific hierarchy_node. If the tenant's phone
// doesn't have a Dormly account yet, one is created here (unverified) —
// when they eventually log in with OTP using that same phone, our
// ContextService will find this tenancy and offer it as a login context.

import { query } from '@config/db';

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
      `SELECT t.*, u.phone, u.name AS user_name, n.name AS node_name
       FROM tenancies t
       JOIN users u ON u.id = t.user_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       WHERE t.property_id = $1
       ORDER BY t.created_at DESC`,
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
    };
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

  async setAgreementUrl(tenancyId: string, url: string) {
    const [tenancy] = await query(
      `UPDATE tenancies SET agreement_pdf_url = $1, updated_at = now() WHERE id = $2 RETURNING *`,
      [url, tenancyId],
    );
    return tenancy;
  }
}