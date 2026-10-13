// shared/startup/schema-readiness.ts
//
// Read-only catalog check for every schema object the backend used to create
// at runtime. One SELECT against pg_catalog / information_schema; never
// writes, never locks application tables.

import { query } from '@config/db';

export type MissingSchemaObject = { object: string; migration: string };

export type SchemaReadiness = {
  missing: MissingSchemaObject[];
  /** invoices.invoice_kind / approved_by present (migration 026 applied). */
  invoiceKind: boolean;
  approvedBy: boolean;
  /** Valid unique indexes on invoices (tenancy_id, period_start). */
  cycleIndexValid: boolean;
  legacyIndexPresent: boolean;
};

const REQUIRED_COLUMNS: [string, string][] = [
  ['notifications.data', '016_notification_data'],
  ['complaints.photo_urls', '017_live_ops_contracts'],
  ['complaints.ticket_number', '017_live_ops_contracts'],
  ['invoice_line_items.charge_kind', '019_invoice_line_charge_kind'],
  ['tenancies.include_past_rent_arrears', '019_invoice_line_charge_kind'],
  ['invoices.sent_at', '025_invoice_review_workflow'],
  ['invoices.is_auto_generated', '025_invoice_review_workflow'],
  ['invoices.overdue_notified_at', '025_invoice_review_workflow'],
];

const REQUIRED_TABLES: [string, string][] = [
  ['mess_menus', '017_live_ops_contracts'],
  ['meter_readings', '017_live_ops_contracts'],
  ['gate_passes', '018_gate_passes'],
];

const OPTIONAL_COLUMNS = ['invoices.invoice_kind', 'invoices.approved_by'];

const CYCLE_INDEX = 'invoices_cycle_tenancy_period_start_uniq';
const LEGACY_INDEX = 'invoices_tenancy_period_start_uniq';

type CatalogRow = {
  columns: string[] | null;
  tables: string[] | null;
  charge_kind_type: boolean;
  complaint_assigned: boolean;
  unique_indexes: string[] | null;
};

export const SCHEMA_READINESS_SQL = `
  SELECT
    (SELECT array_agg(c.table_name || '.' || c.column_name)
       FROM information_schema.columns c
      WHERE c.table_schema = 'public'
        AND (c.table_name || '.' || c.column_name) = ANY($1::text[])) AS columns,
    (SELECT array_agg(cl.relname::text)
       FROM pg_class cl JOIN pg_namespace n ON n.oid = cl.relnamespace
      WHERE n.nspname = 'public' AND cl.relkind IN ('r', 'p')
        AND cl.relname = ANY($2::text[])) AS tables,
    EXISTS (
      SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
       WHERE n.nspname = 'public' AND t.typname = 'invoice_charge_kind'
    ) AS charge_kind_type,
    EXISTS (
      SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
       WHERE t.typname = 'complaint_status' AND e.enumlabel = 'assigned'
    ) AS complaint_assigned,
    (SELECT array_agg(cl.relname::text)
       FROM pg_index ix
       JOIN pg_class cl ON cl.oid = ix.indexrelid
       JOIN pg_namespace n ON n.oid = cl.relnamespace
      WHERE n.nspname = 'public' AND ix.indisunique AND ix.indisvalid AND ix.indisready
        AND cl.relname = ANY($3::text[])) AS unique_indexes`;

export async function checkSchemaReadiness(): Promise<SchemaReadiness> {
  const [row] = await query<CatalogRow>(SCHEMA_READINESS_SQL, [
    [...REQUIRED_COLUMNS.map(([c]) => c), ...OPTIONAL_COLUMNS],
    REQUIRED_TABLES.map(([t]) => t),
    [CYCLE_INDEX, LEGACY_INDEX],
  ]);
  const columns = new Set(row?.columns ?? []);
  const tables = new Set(row?.tables ?? []);
  const indexes = new Set(row?.unique_indexes ?? []);

  const missing: MissingSchemaObject[] = [
    ...REQUIRED_COLUMNS.filter(([c]) => !columns.has(c)).map(([object, migration]) => ({
      object: `column ${object}`,
      migration,
    })),
    ...REQUIRED_TABLES.filter(([t]) => !tables.has(t)).map(([object, migration]) => ({
      object: `table ${object}`,
      migration,
    })),
  ];
  if (!row?.charge_kind_type) {
    missing.push({ object: 'type invoice_charge_kind', migration: '019_invoice_line_charge_kind' });
  }
  if (!row?.complaint_assigned) {
    missing.push({ object: "enum value complaint_status 'assigned'", migration: '017_live_ops_contracts' });
  }
  const cycleIndexValid = indexes.has(CYCLE_INDEX);
  const legacyIndexPresent = indexes.has(LEGACY_INDEX);
  // Concurrent draft generation relies on ON CONFLICT against one of these.
  if (!cycleIndexValid && !legacyIndexPresent) {
    missing.push({
      object: `unique index on invoices (tenancy_id, period_start): ${CYCLE_INDEX} or ${LEGACY_INDEX}`,
      migration: '026_invoice_kind_and_approval (or 025_invoice_review_workflow)',
    });
  }

  return {
    missing,
    invoiceKind: columns.has('invoices.invoice_kind'),
    approvedBy: columns.has('invoices.approved_by'),
    cycleIndexValid,
    legacyIndexPresent,
  };
}
