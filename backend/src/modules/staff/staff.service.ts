// modules/staff/staff.service.ts
//
// Assigns a Manager or Staff member to ONE specific property (never the
// whole organization) — this is the property-level scoping the RBAC design
// relies on. If the phone has no Dormly account yet, one is created here,
// mirroring how tenancies are created.
//
// Every assignment starts as a 'pending' invitation and grants no access
// until the invited user accepts it (only 'active' rows become workspaces and
// pass the property guard). Changing an existing member's role is a new
// invitation too.

import { query } from '@config/db';
import { createNotification } from '@modules/notifications/notify';

/** Invite/accept/decline/remove failures, mapped to [status] by the controllers. */
export class StaffInviteError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

type Assignment = { id: string; role: string; status: string };

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

    const managesAlready = (await query(
      `SELECT 1 FROM memberships m
       JOIN properties p ON p.organization_id = m.organization_id
       WHERE p.id = $1 AND m.user_id = $2 AND m.role IN ('owner', 'admin')`,
      [propertyId, user.id],
    ))[0];
    if (user.id === assignedBy || managesAlready) {
      throw new StaffInviteError(
        'This number already has owner access to this property.',
        400,
      );
    }

    const existing = (await query<Assignment>(
      `SELECT id, role, status FROM property_staff_assignments
       WHERE property_id = $1 AND user_id = $2`,
      [propertyId, user.id],
    ))[0];

    let assignment: Assignment;
    if (existing && existing.role === role) {
      if (existing.status === 'active') return existing;
      assignment = existing;
    } else if (existing) {
      [assignment] = await query<Assignment>(
        `UPDATE property_staff_assignments
         SET role = $1, status = 'pending', assigned_by = $3
         WHERE id = $2 RETURNING *`,
        [role, existing.id, assignedBy],
      );
    } else {
      [assignment] = await query<Assignment>(
        `INSERT INTO property_staff_assignments (user_id, property_id, role, assigned_by, status)
         VALUES ($1, $2, $3, $4, 'pending') RETURNING *`,
        [user.id, propertyId, role, assignedBy],
      );
    }

    await this.notifyInvitee(user.id, propertyId, assignment.id, role);
    return assignment;
  }

  private async notifyInvitee(
    userId: string,
    propertyId: string,
    assignmentId: string,
    role: string,
  ) {
    const property = (await query<{ name: string }>(
      `SELECT name FROM properties WHERE id = $1`,
      [propertyId],
    ))[0];
    const roleLabel = role === 'manager' ? 'Manager' : 'Staff';
    await createNotification({
      userId,
      propertyId,
      type: 'staff_invitation',
      title: 'You have a team invitation',
      body: `You've been invited to join ${property?.name ?? 'a property'} as ${roleLabel}. Accept it to get access.`,
      data: { assignmentId, role },
    });
  }

  /** Removes a member or withdraws an invitation, only within [propertyId]. */
  async remove(propertyId: string, assignmentId: string) {
    const rows = await query(
      `DELETE FROM property_staff_assignments
       WHERE id = $1 AND property_id = $2 RETURNING id`,
      [assignmentId, propertyId],
    );
    if (!rows[0]) throw new StaffInviteError('Team member not found.', 404);
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

  /** Only the invited user can accept, and only a still-pending invitation. */
  async accept(assignmentId: string, userId: string) {
    const [assignment] = await query(
      `UPDATE property_staff_assignments SET status = 'active'
       WHERE id = $1 AND user_id = $2 AND status = 'pending' RETURNING *`,
      [assignmentId, userId],
    );
    if (!assignment) throw new StaffInviteError('Invitation not found.', 404);
    return assignment;
  }

  async decline(assignmentId: string, userId: string) {
    const rows = await query(
      `DELETE FROM property_staff_assignments
       WHERE id = $1 AND user_id = $2 AND status = 'pending' RETURNING id`,
      [assignmentId, userId],
    );
    if (!rows[0]) throw new StaffInviteError('Invitation not found.', 404);
  }

  /** Role of an accepted assignment, or null (pending, removed, never invited). */
  async activeRole(userId: string, propertyId: string): Promise<string | null> {
    const row = (await query<{ role: string }>(
      `SELECT role FROM property_staff_assignments
       WHERE user_id = $1 AND property_id = $2 AND status = 'active'`,
      [userId, propertyId],
    ))[0];
    return row?.role ?? null;
  }
}
