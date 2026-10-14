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

/**
 * Columns any viewer of a complaint may receive. Tenant-facing queries list
 * these explicitly (never `c.*`) so assignment columns can't reach tenants.
 */
const COMPLAINT_COLUMNS = [
  'id', 'property_id', 'node_id', 'raised_by', 'category', 'description',
  'priority', 'status', 'resolution_note', 'photo_urls', 'ticket_number',
  'created_at', 'updated_at', 'resolved_at',
];
const columns = (alias?: string) =>
  COMPLAINT_COLUMNS.map((c) => (alias ? `${alias}.${c}` : c)).join(', ');

export type ComplaintSchemaCaps = { assignment: boolean; comments: boolean };

const CAPS_TTL_MS = 5 * 60_000;
let capsCache: { at: number; value: Promise<ComplaintSchemaCaps> } | null = null;

/**
 * Objects from migration 027 (applied manually). Cached briefly so the app
 * picks them up without a restart once the migration has been run.
 */
export function complaintSchemaCaps(): Promise<ComplaintSchemaCaps> {
  const now = Date.now();
  if (!capsCache || now - capsCache.at > CAPS_TTL_MS) {
    const value = query<{ assignment: boolean; comments: boolean }>(
      `SELECT
         EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'complaints'
                   AND column_name = 'assigned_to') AS assignment,
         to_regclass('public.complaint_comments') IS NOT NULL AS comments`,
    )
      .then(([row]) => ({ assignment: !!row?.assignment, comments: !!row?.comments }))
      .catch(() => {
        capsCache = null;
        return { assignment: false, comments: false };
      });
    capsCache = { at: now, value };
  }
  return capsCache.value;
}

export function resetComplaintSchemaCaps() {
  capsCache = null;
}

/**
 * Current eligible role of a user for a property's complaints: the property's
 * organization owner/admin, or an active manager/staff assignment on it.
 * NULL when the user is not (or no longer) eligible.
 */
function eligibleRoleSql(userExpr: string, propertyExpr: string) {
  return `(SELECT r.role FROM (
      SELECT m.role::text AS role, 0 AS rank
      FROM memberships m
      JOIN properties p ON p.id = ${propertyExpr}
      WHERE m.user_id = ${userExpr} AND m.organization_id = p.organization_id
        AND m.role::text IN ('owner', 'admin')
      UNION ALL
      SELECT psa.role::text, 1
      FROM property_staff_assignments psa
      WHERE psa.user_id = ${userExpr} AND psa.property_id = ${propertyExpr}
        AND psa.status = 'active' AND psa.role::text IN ('manager', 'staff')
    ) r ORDER BY r.rank LIMIT 1)`;
}

export type CommentAudience = 'team' | 'tenant';
export type AssignResult = 'assigned' | 'unassigned' | 'unchanged' | 'ineligible';

export class ComplaintService {
  /** Property team view: reporter details and, once 027 is applied, the assignee. */
  async listByProperty(propertyId: string, complaintId?: string) {
    await ensureLiveOpsSchema();
    const caps = await complaintSchemaCaps();
    const params: unknown[] = [propertyId];
    if (complaintId) params.push(complaintId);
    return query(
      `SELECT c.*, n.name AS node_name, u.phone AS raised_by_phone,
              u.name AS raised_by_name, occ.full_name AS tenant_name
              ${caps.assignment
                ? `, au.name AS assignee_name, ${eligibleRoleSql('c.assigned_to', 'c.property_id')} AS assignee_role`
                : ''}
       FROM complaints c
       JOIN hierarchy_nodes n ON n.id = c.node_id
       JOIN users u ON u.id = c.raised_by
       ${caps.assignment ? 'LEFT JOIN users au ON au.id = c.assigned_to' : ''}
       LEFT JOIN LATERAL (
         SELECT t.full_name
         FROM tenancies t
         WHERE t.node_id = c.node_id
           AND t.property_id = c.property_id
           AND t.status = 'active'
         ORDER BY t.created_at DESC
         LIMIT 1
       ) occ ON true
       WHERE c.property_id = $1 ${complaintId ? 'AND c.id = $2' : ''}
       ORDER BY c.created_at DESC`,
      params,
    ).then((rows: any[]) =>
      rows.map((r) =>
        caps.assignment
          ? { ...r, assignee_active: r.assigned_to ? r.assignee_role != null : null }
          : r,
      ),
    );
  }

  /** The tenant's own complaints at one property, without other residents' details. */
  async listForTenant(propertyId: string, userId: string) {
    await ensureLiveOpsSchema();
    const caps = await complaintSchemaCaps();
    return query(
      `SELECT ${columns('c')}, n.name AS node_name
              ${caps.assignment ? ', (c.assigned_to IS NOT NULL) AS is_assigned' : ''}
       FROM complaints c
       JOIN hierarchy_nodes n ON n.id = c.node_id
       WHERE c.property_id = $1 AND c.raised_by = $2
       ORDER BY c.created_at DESC`,
      [propertyId, userId],
    );
  }

  /** Property and unit of the user's active tenancy, or null when it is not theirs or not active. */
  async tenantPlacement(tenancyId: string, userId: string) {
    const rows = await query<{ property_id: string; node_id: string | null }>(
      `SELECT property_id, node_id FROM tenancies
       WHERE id = $1::uuid AND user_id = $2::uuid AND status = 'active'`,
      [tenancyId, userId],
    );
    const row = rows[0];
    return row?.node_id ? { propertyId: row.property_id, nodeId: row.node_id } : null;
  }

  async nodeInProperty(nodeId: string, propertyId: string) {
    const rows = await query(
      `SELECT 1 FROM hierarchy_nodes WHERE id = $1::uuid AND property_id = $2::uuid`,
      [nodeId, propertyId],
    );
    return rows.length > 0;
  }

  /** Who raised a complaint of this property, or null when it is not this property's. */
  async raisedBy(propertyId: string, complaintId: string) {
    const rows = await query<{ raised_by: string }>(
      `SELECT raised_by FROM complaints WHERE id = $1::uuid AND property_id = $2::uuid`,
      [complaintId, propertyId],
    );
    return rows[0] ? String(rows[0].raised_by) : null;
  }

  async listByUser(userId: string) {
    await ensureLiveOpsSchema();
    const caps = await complaintSchemaCaps();
    return query(
      `SELECT ${columns('c')}, n.name AS node_name
              ${caps.assignment ? ', (c.assigned_to IS NOT NULL) AS is_assigned' : ''}
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
      `SELECT ${columns('c')}, n.name AS node_name
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
       RETURNING ${columns()}`,
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
      `UPDATE complaints SET ticket_number = $1 WHERE id = $2 RETURNING ${columns()}`,
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
    propertyId: string,
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
       WHERE id = $4 AND property_id = $5
       RETURNING *`,
      [status, resolutionNote ?? null, resolvedAt, complaintId, propertyId],
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

  /** People a property's complaints can be assigned to: id, name and role only. */
  async listAssignees(propertyId: string) {
    const rows = await query<{ user_id: string; name: string | null; role: string; rank: number }>(
      `SELECT DISTINCT ON (u.id) u.id AS user_id, u.name, r.role, r.rank
       FROM (
         SELECT m.user_id, m.role::text AS role, 0 AS rank
         FROM memberships m
         JOIN properties p ON p.id = $1::uuid
         WHERE m.organization_id = p.organization_id AND m.role::text IN ('owner', 'admin')
         UNION ALL
         SELECT psa.user_id, psa.role::text, 1
         FROM property_staff_assignments psa
         WHERE psa.property_id = $1::uuid AND psa.status = 'active'
           AND psa.role::text IN ('manager', 'staff')
       ) r
       JOIN users u ON u.id = r.user_id
       ORDER BY u.id, r.rank`,
      [propertyId],
    );
    const order = ['owner', 'admin', 'manager', 'staff'];
    return rows
      .map(({ user_id, name, role }) => ({ user_id: String(user_id), name, role }))
      .sort(
        (a, b) =>
          order.indexOf(a.role) - order.indexOf(b.role) ||
          (a.name ?? '').localeCompare(b.name ?? ''),
      );
  }

  /**
   * Assigns (or with null, unassigns) a complaint of this property. Eligibility
   * is checked inside the same statement that writes, and the change is
   * recorded as an internal activity entry.
   */
  async assign(
    propertyId: string,
    complaintId: string,
    assigneeUserId: string | null,
    actor: { userId: string; role: string },
  ): Promise<AssignResult> {
    if (assigneeUserId === null) {
      const rows = await query(
        `WITH old AS (
           SELECT c.assigned_to, u.name
           FROM complaints c LEFT JOIN users u ON u.id = c.assigned_to
           WHERE c.id = $1::uuid AND c.property_id = $2::uuid
         ), upd AS (
           UPDATE complaints c
           SET assigned_to = NULL, assigned_by = $3::uuid, assigned_at = now()
           WHERE c.id = $1::uuid AND c.property_id = $2::uuid AND c.assigned_to IS NOT NULL
           RETURNING c.id, c.property_id
         )
         INSERT INTO complaint_comments
           (complaint_id, property_id, author_user_id, author_role, kind, visibility, meta)
         SELECT upd.id, upd.property_id, $3::uuid, $4, 'unassigned', 'internal',
                jsonb_build_object('previous_user_id', old.assigned_to::text,
                                   'previous_name', old.name)
         FROM upd, old
         RETURNING id`,
        [complaintId, propertyId, actor.userId, actor.role],
      );
      return rows.length > 0 ? 'unassigned' : 'unchanged';
    }

    const rows = await query(
      `WITH target AS (
         SELECT ${eligibleRoleSql('$3::uuid', '$2::uuid')} AS role,
                (SELECT name FROM users WHERE id = $3::uuid) AS name
       ), upd AS (
         UPDATE complaints c
         SET assigned_to = $3::uuid, assigned_by = $4::uuid, assigned_at = now()
         FROM target
         WHERE c.id = $1::uuid AND c.property_id = $2::uuid
           AND target.role IS NOT NULL
           AND c.assigned_to IS DISTINCT FROM $3::uuid
         RETURNING c.id, c.property_id, target.name, target.role
       )
       INSERT INTO complaint_comments
         (complaint_id, property_id, author_user_id, author_role, kind, visibility, meta)
       SELECT id, property_id, $4::uuid, $5, 'assigned', 'internal',
              jsonb_build_object('assignee_user_id', $3::text,
                                 'assignee_name', name, 'assignee_role', role)
       FROM upd
       RETURNING id`,
      [complaintId, propertyId, assigneeUserId, actor.userId, actor.role],
    );
    if (rows.length > 0) return 'assigned';

    const [current] = await query<{ eligible: boolean; same: boolean }>(
      `SELECT ${eligibleRoleSql('$3::uuid', '$2::uuid')} IS NOT NULL AS eligible,
              EXISTS (SELECT 1 FROM complaints
                      WHERE id = $1::uuid AND property_id = $2::uuid
                        AND assigned_to = $3::uuid) AS same`,
      [complaintId, propertyId, assigneeUserId],
    );
    return current?.eligible && current.same ? 'unchanged' : 'ineligible';
  }

  async notifyAssignee(propertyId: string, complaint: any) {
    await createNotification({
      userId: String(complaint.assigned_to),
      propertyId,
      type: 'complaint_assigned',
      title: 'Complaint assigned to you',
      body: `${complaint.node_name ?? 'Unit'} • ${String(complaint.description ?? complaint.category ?? '').slice(0, 120)}`,
      data: {
        complaint_id: String(complaint.id),
        complaintId: String(complaint.id),
        property_id: propertyId,
        propertyId,
        route: '/complaints',
      },
    }).catch((err) => console.warn('[complaints] assignee notify failed:', err));
  }

  /** Activity entries for a complaint of this property, shaped for the audience. */
  async listComments(propertyId: string, complaintId: string, audience: CommentAudience) {
    if (audience === 'tenant') {
      return query(
        `SELECT cc.id, cc.complaint_id, cc.kind, cc.body, cc.created_at,
                CASE WHEN cc.author_role = 'tenant' THEN 'tenant' ELSE 'team' END AS author_role
         FROM complaint_comments cc
         WHERE cc.complaint_id = $1::uuid AND cc.property_id = $2::uuid
           AND cc.kind = 'comment' AND cc.visibility = 'tenant_visible'
         ORDER BY cc.created_at, cc.id`,
        [complaintId, propertyId],
      );
    }
    return query(
      `SELECT cc.id, cc.complaint_id, cc.kind, cc.visibility, cc.body, cc.author_role,
              cc.meta, cc.created_at, u.name AS author_name
       FROM complaint_comments cc
       LEFT JOIN users u ON u.id = cc.author_user_id
       WHERE cc.complaint_id = $1::uuid AND cc.property_id = $2::uuid
       ORDER BY cc.created_at, cc.id`,
      [complaintId, propertyId],
    );
  }

  async addComment(
    propertyId: string,
    complaintId: string,
    actor: { userId: string; role: string },
    body: string,
    visibility: 'internal' | 'tenant_visible',
  ) {
    const rows = await query<{ id: string }>(
      `INSERT INTO complaint_comments
         (complaint_id, property_id, author_user_id, author_role, kind, visibility, body)
       SELECT c.id, c.property_id, $3::uuid, $4, 'comment', $5, $6
       FROM complaints c
       WHERE c.id = $1::uuid AND c.property_id = $2::uuid
       RETURNING id`,
      [complaintId, propertyId, actor.userId, actor.role, visibility, body],
    );
    return rows[0] ? String(rows[0].id) : null;
  }
}
