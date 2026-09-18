// modules/gate-passes/gate-passes.service.ts
import { query } from '@config/db';
import {
  createNotification,
  ensureLiveOpsSchema,
  notifyPropertyOwners,
} from '@modules/notifications/notify';

export class GatePassesService {
  async listByProperty(propertyId: string) {
    await ensureLiveOpsSchema();
    return query(
      `SELECT gp.*, n.name AS unit_name, u.name AS requested_by_name
       FROM gate_passes gp
       JOIN hierarchy_nodes n ON n.id = gp.unit_id
       JOIN users u ON u.id = gp.requested_by
       WHERE gp.property_id = $1
       ORDER BY gp.created_at DESC
       LIMIT 100`,
      [propertyId],
    );
  }

  async listMine(userId: string, tenancyId: string) {
    await ensureLiveOpsSchema();
    return query(
      `SELECT * FROM gate_passes
       WHERE requested_by = $1 OR tenancy_id = $2
       ORDER BY created_at DESC
       LIMIT 50`,
      [userId, tenancyId],
    );
  }

  async create(input: {
    propertyId: string;
    unitId: string;
    tenancyId: string;
    requestedBy: string;
    visitorName: string;
    purpose: string;
    notes?: string;
    validUntil?: string | null;
  }) {
    await ensureLiveOpsSchema();
    const [row] = await query<any>(
      `INSERT INTO gate_passes
         (property_id, unit_id, tenancy_id, requested_by, visitor_name, purpose, notes, valid_until)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING *`,
      [
        input.propertyId,
        input.unitId,
        input.tenancyId,
        input.requestedBy,
        input.visitorName.trim(),
        input.purpose.trim() || 'visitor',
        input.notes?.trim() || null,
        input.validUntil ?? null,
      ],
    );

    const unit = await query<{ name: string }>(
      `SELECT name FROM hierarchy_nodes WHERE id = $1`,
      [input.unitId],
    );
    await notifyPropertyOwners({
      propertyId: input.propertyId,
      type: 'gate_pass',
      title: `Gate pass: ${input.visitorName}`,
      body: `${unit[0]?.name ?? 'Unit'} • ${input.purpose}`,
      data: {
        gate_pass_id: String(row.id),
        property_id: input.propertyId,
        route: '/complaints',
      },
    }).catch((e) => console.warn('[gate-pass] owner notify failed:', e));

    return row;
  }

  async decide(
    propertyId: string,
    gatePassId: string,
    status: 'approved' | 'denied',
    decidedBy: string,
  ) {
    await ensureLiveOpsSchema();
    const [row] = await query<any>(
      `UPDATE gate_passes
       SET status = $1, decided_by = $2, decided_at = now(), updated_at = now()
       WHERE id = $3 AND property_id = $4
       RETURNING *`,
      [status, decidedBy, gatePassId, propertyId],
    );
    if (!row) return null;

    await createNotification({
      userId: String(row.requested_by),
      propertyId,
      type: 'gate_pass_status',
      title: status === 'approved' ? 'Gate pass approved' : 'Gate pass denied',
      body: `${row.visitor_name} • ${status}`,
      data: {
        gate_pass_id: String(row.id),
        property_id: propertyId,
        route: '/tenant-home',
        status,
      },
    }).catch((e) => console.warn('[gate-pass] tenant notify failed:', e));

    return row;
  }
}
