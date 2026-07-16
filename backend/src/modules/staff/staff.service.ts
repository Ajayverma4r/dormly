// modules/staff/staff.service.ts
//
// Assigns a Manager or Staff member to ONE specific property (never the
// whole organization) — this is the property-level scoping the RBAC design
// relies on. If the phone has no Dormly account yet, one is created here,
// mirroring how tenancies are created.

import { query } from '@config/db';

export class StaffService {
  async listForProperty(propertyId: string) {
    return query(
      `SELECT psa.*, u.phone, u.name
       FROM property_staff_assignments psa
       JOIN users u ON u.id = psa.user_id
       WHERE psa.property_id = $1
       ORDER BY psa.created_at DESC`,
      [propertyId],
    );
  }

  async assign(propertyId: string, phone: string, role: 'manager' | 'staff', assignedBy: string) {
    let user = (await query<{ id: string }>(`SELECT id FROM users WHERE phone = $1`, [phone]))[0];
    if (!user) {
      user = (await query<{ id: string }>(
        `INSERT INTO users (phone) VALUES ($1) RETURNING id`,
        [phone],
      ))[0];
    }

    const existing = (await query<{ id: string }>(
      `SELECT id FROM property_staff_assignments WHERE property_id = $1 AND user_id = $2`,
      [propertyId, user.id],
    ))[0];

    if (existing) {
      const [updated] = await query(
        `UPDATE property_staff_assignments SET role = $1 WHERE id = $2 RETURNING *`,
        [role, existing.id],
      );
      return updated;
    }

    const [assignment] = await query(
      `INSERT INTO property_staff_assignments (user_id, property_id, role, assigned_by)
       VALUES ($1,$2,$3,$4) RETURNING *`,
      [user.id, propertyId, role, assignedBy],
    );
    return assignment;
  }

  async remove(assignmentId: string) {
    await query(`DELETE FROM property_staff_assignments WHERE id = $1`, [assignmentId]);
  }

  async listPendingForUser(userId: string) {
    return query(
      `SELECT psa.*, p.name AS property_name
       FROM property_staff_assignments psa
       JOIN properties p ON p.id = psa.property_id
       WHERE psa.user_id = $1 AND psa.status = 'pending'`,
      [userId],
    );
  }

  async accept(assignmentId: string, userId: string) {
    const [assignment] = await query(
      `UPDATE property_staff_assignments SET status = 'active'
       WHERE id = $1 AND user_id = $2 RETURNING *`,
      [assignmentId, userId],
    );
    return assignment;
  }

  async decline(assignmentId: string, userId: string) {
    await query(
      `DELETE FROM property_staff_assignments WHERE id = $1 AND user_id = $2`,
      [assignmentId, userId],
    );
  }
}