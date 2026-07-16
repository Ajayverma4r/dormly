// modules/complaints/complaint.service.ts
import { query } from '@config/db';

export class ComplaintService {
  async listByProperty(propertyId: string) {
    return query(
      `SELECT c.*, n.name AS node_name, u.phone AS raised_by_phone
       FROM complaints c
       JOIN hierarchy_nodes n ON n.id = c.node_id
       JOIN users u ON u.id = c.raised_by
       WHERE c.property_id = $1
       ORDER BY c.created_at DESC`,
      [propertyId],
    );
  }

  async listByUser(userId: string) {
    return query(
      `SELECT c.*, n.name AS node_name
       FROM complaints c
       JOIN hierarchy_nodes n ON n.id = c.node_id
       WHERE c.raised_by = $1
       ORDER BY c.created_at DESC`,
      [userId],
    );
  }

  async create(propertyId: string, nodeId: string, raisedBy: string, category: string, description: string, priority: string) {
    const [complaint] = await query(
      `INSERT INTO complaints (property_id, node_id, raised_by, category, description, priority)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [propertyId, nodeId, raisedBy, category, description, priority],
    );
    return complaint;
  }

  async updateStatus(complaintId: string, status: string, resolutionNote?: string) {
    const resolvedAt = status === 'resolved' || status === 'closed' ? new Date().toISOString() : null;
    const [complaint] = await query(
      `UPDATE complaints
       SET status = $1, resolution_note = COALESCE($2, resolution_note), resolved_at = COALESCE($3, resolved_at), updated_at = now()
       WHERE id = $4 RETURNING *`,
      [status, resolutionNote ?? null, resolvedAt, complaintId],
    );
    return complaint;
  }
}