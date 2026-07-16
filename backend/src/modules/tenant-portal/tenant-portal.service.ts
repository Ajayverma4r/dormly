// modules/tenant-portal/tenant-portal.service.ts
//
// Deliberately separate from modules/tenancies (the owner-side CRUD). This
// service only ever looks up ONE tenancy — the one on the caller's own
// scoped token (req.ctxId) — and never accepts a tenancyId from the request.
// That's what makes it safe for a tenant role to call directly.

import { query } from '@config/db';

export class TenantPortalService {
  async getMyTenancy(tenancyId: string) {
    const rows = await query<any>(
      `SELECT
         t.*,
         n.name AS node_name,
         p.id AS property_id,
         p.name AS property_name,
         p.address AS property_address,
         p.city AS property_city,
         o.name AS organization_name,
         owner_u.phone AS owner_phone,
         owner_u.name AS owner_name
       FROM tenancies t
       JOIN hierarchy_nodes n ON n.id = t.node_id
       JOIN properties p ON p.id = t.property_id
       JOIN organizations o ON o.id = p.organization_id
       JOIN users owner_u ON owner_u.id = o.owner_user_id
       WHERE t.id = $1`,
      [tenancyId],
    );
    return rows[0] ?? null;
  }
}