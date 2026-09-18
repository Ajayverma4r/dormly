// modules/complaints/complaint.service.ts
import { query } from '@config/db';
import {
  createNotification,
  ensureLiveOpsSchema,
  notifyPropertyOwners,
} from '@modules/notifications/notify';

function ticketFromId(id: string): string {
  return `CMP-${id.replace(/-/g, '').slice(0, 8).toUpperCase()}`;
}

export class ComplaintService {
  async listByProperty(propertyId: string) {
    await ensureLiveOpsSchema();
    return query(
      `SELECT c.*, n.name AS node_name, u.phone AS raised_by_phone,
              u.name AS raised_by_name, occ.full_name AS tenant_name
       FROM complaints c
       JOIN hierarchy_nodes n ON n.id = c.node_id
       JOIN users u ON u.id = c.raised_by
       LEFT JOIN LATERAL (
         SELECT t.full_name
         FROM tenancies t
         WHERE t.node_id = c.node_id
           AND t.property_id = c.property_id
           AND t.status = 'active'
         ORDER BY t.created_at DESC
         LIMIT 1
       ) occ ON true
       WHERE c.property_id = $1
       ORDER BY c.created_at DESC`,
      [propertyId],
    );
  }

  async listByUser(userId: string) {
    await ensureLiveOpsSchema();
    return query(
      `SELECT c.*, n.name AS node_name
       FROM complaints c
       JOIN hierarchy_nodes n ON n.id = c.node_id
       WHERE c.raised_by = $1
       ORDER BY c.created_at DESC`,
      [userId],
    );
  }

  async getById(complaintId: string) {
    await ensureLiveOpsSchema();
    const rows = await query<any>(
      `SELECT c.*, n.name AS node_name
       FROM complaints c
       JOIN hierarchy_nodes n ON n.id = c.node_id
       WHERE c.id = $1`,
      [complaintId],
    );
    return rows[0] ?? null;
  }

  async create(
    propertyId: string,
    nodeId: string,
    raisedBy: string,
    category: string,
    description: string,
    priority: string,
    photoUrls: string[] = [],
  ) {
    await ensureLiveOpsSchema();
    const [complaint] = await query<any>(
      `INSERT INTO complaints
         (property_id, node_id, raised_by, category, description, priority, photo_urls, ticket_number)
       VALUES ($1,$2,$3,$4,$5,$6,$7::text[], $8)
       RETURNING *`,
      [
        propertyId,
        nodeId,
        raisedBy,
        category,
        description,
        priority,
        photoUrls,
        'PENDING',
      ],
    );

    const ticket = ticketFromId(String(complaint.id));
    const [updated] = await query<any>(
      `UPDATE complaints SET ticket_number = $1 WHERE id = $2 RETURNING *`,
      [ticket, complaint.id],
    );
    const row = updated ?? { ...complaint, ticket_number: ticket };

    const nodeRows = await query<{ name: string }>(
      `SELECT name FROM hierarchy_nodes WHERE id = $1`,
      [nodeId],
    );
    const room = nodeRows[0]?.name ?? 'Unit';

    await notifyPropertyOwners({
      propertyId,
      type: 'complaint_created',
      title: `New Complaint: ${category}`,
      body: `${room} • ${description.slice(0, 120)}`,
      data: {
        complaint_id: String(row.id),
        complaintId: String(row.id),
        property_id: propertyId,
        propertyId,
        route: '/complaints',
        ticket_number: ticket,
      },
    }).catch((err) => console.warn('[complaints] owner notify failed:', err));

    return row;
  }

  async updateStatus(
    complaintId: string,
    status: string,
    resolutionNote?: string,
  ) {
    await ensureLiveOpsSchema();
    const resolvedAt =
      status === 'resolved' || status === 'closed'
        ? new Date().toISOString()
        : null;
    const [complaint] = await query<any>(
      `UPDATE complaints
       SET status = $1::complaint_status,
           resolution_note = COALESCE($2, resolution_note),
           resolved_at = COALESCE($3, resolved_at),
           updated_at = now()
       WHERE id = $4
       RETURNING *`,
      [status, resolutionNote ?? null, resolvedAt, complaintId],
    );
    if (!complaint) return null;

    const statusLabel = status.replace(/_/g, ' ');
    await createNotification({
      userId: String(complaint.raised_by),
      propertyId: String(complaint.property_id),
      type: 'complaint_status',
      title: `Complaint ${statusLabel}`,
      body:
        resolutionNote?.trim() ||
        `Your ticket ${complaint.ticket_number ?? ticketFromId(String(complaint.id))} is now ${statusLabel}.`,
      data: {
        complaint_id: String(complaint.id),
        complaintId: String(complaint.id),
        property_id: String(complaint.property_id),
        propertyId: String(complaint.property_id),
        route: '/tenant-home',
        status,
      },
    }).catch((err) => console.warn('[complaints] tenant notify failed:', err));

    return complaint;
  }
}
