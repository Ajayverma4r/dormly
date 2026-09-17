// modules/tenant-portal/tenant-portal.service.ts
//
// Deliberately separate from modules/tenancies (the owner-side CRUD). This
// service only ever looks up ONE tenancy — the one on the caller's own
// scoped token (req.ctxId) — and never accepts a tenancyId from the request.

import { query } from '@config/db';
import { notifyOwnersOfMoveOut } from '@modules/notifications/move-out-notifications';

function startOfLocalDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

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
         o.id AS organization_id,
         o.owner_user_id AS owner_user_id,
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

  /**
   * Tenant submits a move-out request.
   * - notice_given_at (requestedAt) is set once and never overwritten.
   * - planned_move_out_at is the proposed exit date (must be >= today).
   * - Always ensures owner notifications exist (even if request was already pending).
   */
  async requestMoveOut(
    tenancyId: string,
    input: { proposedExitDate: string; isEmergency?: boolean; reason?: string },
  ) {
    const existing = await this.getMyTenancy(tenancyId);
    if (!existing) throw new Error('Tenancy not found');
    if (existing.status !== 'active') {
      throw new Error('Only active tenancies can request move-out.');
    }

    const alreadyFiled =
      existing.move_out_request_status === 'pending' ||
      existing.move_out_request_status === 'approved' ||
      existing.move_out_request_status === 'modified_by_mutual_agreement';

    // If already on file, still ensure the owner notification exists, then return.
    if (alreadyFiled) {
      console.log(
        `[tenant-portal] move-out already on file tenancy=${tenancyId}; ensuring notifications`,
      );
      const ensured = await notifyOwnersOfMoveOut(existing);
      console.log(
        `[tenant-portal] ensured move-out notifications count=${ensured}`,
      );
      throw new Error('A move-out request is already on file for this tenancy.');
    }

    const proposed = new Date(input.proposedExitDate);
    if (Number.isNaN(proposed.getTime())) {
      throw new Error('Invalid proposed exit date.');
    }
    const today = startOfLocalDay(new Date());
    const proposedDay = startOfLocalDay(proposed);
    if (proposedDay < today) {
      throw new Error('Proposed move-out date cannot be in the past.');
    }
    const max = new Date(today);
    max.setDate(max.getDate() + 90);
    if (proposedDay > max) {
      throw new Error('Proposed move-out date cannot be more than 90 days ahead.');
    }

    // Lock requestedAt: only set notice_given_at when still null.
    const rows = await query<any>(
      `UPDATE tenancies SET
         notice_given_at = COALESCE(notice_given_at, now()),
         planned_move_out_at = $2,
         move_out_request_status = 'pending',
         move_out_is_emergency = $3,
         move_out_reason = $4,
         updated_at = now()
       WHERE id = $1 AND status = 'active'
       RETURNING id`,
      [
        tenancyId,
        proposedDay.toISOString(),
        input.isEmergency === true,
        input.reason?.trim() || null,
      ],
    );
    if (!rows[0]) throw new Error('Could not save move-out request.');

    const updated = await this.getMyTenancy(tenancyId);
    if (!updated) throw new Error('Could not reload tenancy after move-out request.');

    console.log(
      `[tenant-portal] move-out saved tenancy=${tenancyId} owner=${updated.owner_user_id}`,
    );
    try {
      const ensured = await notifyOwnersOfMoveOut(updated);
      console.log(
        `[tenant-portal] move-out notifications ensured=${ensured} owner=${updated.owner_user_id}`,
      );
      if (!ensured) {
        console.error(
          '[tenant-portal] CRITICAL: move-out saved but zero notifications written',
        );
      }
    } catch (err) {
      console.error('[tenant-portal] move-out notification threw:', err);
    }

    return updated;
  }
}
