// modules/auth/context.service.ts
import { query } from '@config/db';

export type ContextType = 'organization' | 'tenancy';

export interface AuthContext {
  type: ContextType;
  id: string;            // organizationId or propertyId (for staff) or tenancyId (for tenant)
  role: string;           // owner | admin | manager | staff | tenant
  label: string;          // human-readable, e.g. "Sunshine Hostel" or "Ajay's Organization"
  propertyId?: string;    // present for manager/staff/tenant contexts
}

export class ContextService {
  async listContextsForUser(userId: string): Promise<AuthContext[]> {
    const contexts: AuthContext[] = [];

    // Owner/Admin contexts: whole organization, every property included.
    const memberships = await query<any>(
      `SELECT m.role, o.id AS organization_id, o.name
       FROM memberships m
       JOIN organizations o ON o.id = m.organization_id
       WHERE m.user_id = $1 AND m.role IN ('owner', 'admin')`,
      [userId],
    );
    for (const m of memberships) {
      contexts.push({
        type: 'organization',
        id: m.organization_id,
        role: m.role,
        label: m.name,
      });
    }

    // Manager/Staff contexts: one per assigned property, NOT the whole org.
    const staffAssignments = await query<any>(
      `SELECT psa.role, p.id AS property_id, p.name
       FROM property_staff_assignments psa
       JOIN properties p ON p.id = psa.property_id
       WHERE psa.user_id = $1 AND psa.status = 'active'`,
      [userId],
    );
    
    for (const s of staffAssignments) {
      contexts.push({
        type: 'organization', // reuses property-scoped org routes, but scoped down at the guard level
        id: s.property_id,
        role: s.role,
        label: s.name,
        propertyId: s.property_id,
      });
    }

    // Tenant contexts: one per active tenancy.
    const tenancies = await query<any>(
      `SELECT t.id AS tenancy_id, t.property_id, p.name AS property_name, n.name AS node_name
       FROM tenancies t
       JOIN properties p ON p.id = t.property_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       WHERE t.user_id = $1 AND t.status = 'active'`,
      [userId],
    );
    for (const t of tenancies) {
      contexts.push({
        type: 'tenancy',
        id: t.tenancy_id,
        role: 'tenant',
        label: `${t.property_name} — ${t.node_name}`,
        propertyId: t.property_id,
      });
    }

    return contexts;
  }
}