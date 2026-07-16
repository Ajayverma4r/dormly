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
  securityDeposit?: number;
  notes?: string;
  status?: 'active' | 'ended' | 'pending';
}

export class TenancyService {
  async listByNode(nodeId: string) {
    return query(
      `SELECT t.*, u.phone
       FROM tenancies t
       JOIN users u ON u.id = t.user_id
       WHERE t.node_id = $1
       ORDER BY t.created_at DESC`,
      [nodeId],
    );
  }

  async listByProperty(propertyId: string) {
    return query(
      `SELECT t.*, u.phone, n.name AS node_name
       FROM tenancies t
       JOIN users u ON u.id = t.user_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       WHERE t.property_id = $1
       ORDER BY t.created_at DESC`,
      [propertyId],
    );
  }

  async create(input: CreateTenancyInput) {
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

  async update(tenancyId: string, input: UpdateTenancyInput) {
    const columnMap: Record<string, string> = {
      fullName: 'full_name', email: 'email', address: 'address', companyName: 'company_name',
      aadhaarNumber: 'aadhaar_number', moveInAt: 'move_in_at', moveOutAt: 'move_out_at',
      securityDeposit: 'security_deposit', notes: 'notes', status: 'status',
    };
    const fields: string[] = [];
    const values: any[] = [];
    let i = 1;
    for (const [key, column] of Object.entries(columnMap)) {
      const value = (input as any)[key];
      if (value !== undefined) {
        fields.push(`${column} = $${i++}`);
        values.push(value);
      }
    }
    fields.push('updated_at = now()');
    values.push(tenancyId);
    const [tenancy] = await query(
      `UPDATE tenancies SET ${fields.join(', ')} WHERE id = $${i} RETURNING *`,
      values,
    );
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