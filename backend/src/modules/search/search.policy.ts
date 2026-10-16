// modules/search/search.policy.ts
//
// Which search categories, filters and result fields each workspace role may
// use. Mirrors the existing route guards: billing and payments are owner /
// admin / manager; the team list is owner / admin in the app; staff get
// operational records only; tenants get their own records only.

export const SEARCH_CATEGORIES = [
  'properties',
  'rooms',
  'tenants',
  'team',
  'complaints',
  'gate_passes',
  'invoices',
  'payments',
  'meter_readings',
  'mess_menu',
] as const;
export type SearchCategory = (typeof SEARCH_CATEGORIES)[number];

export const SEARCH_FILTERS = ['overdue', 'drafts', 'vacant', 'checked_out'] as const;
export type SearchFilter = (typeof SEARCH_FILTERS)[number];

export type SearchRole = 'owner' | 'admin' | 'manager' | 'staff' | 'tenant';

const OWNER_CATEGORIES: SearchCategory[] = [
  'properties', 'rooms', 'tenants', 'team', 'complaints',
  'gate_passes', 'invoices', 'payments', 'meter_readings', 'mess_menu',
];

export const CATEGORIES_BY_ROLE: Record<SearchRole, readonly SearchCategory[]> = {
  owner: OWNER_CATEGORIES,
  admin: OWNER_CATEGORIES,
  manager: [
    'rooms', 'tenants', 'complaints', 'gate_passes',
    'invoices', 'payments', 'meter_readings', 'mess_menu',
  ],
  staff: ['rooms', 'tenants', 'complaints', 'gate_passes', 'meter_readings', 'mess_menu'],
  tenant: ['rooms', 'invoices', 'payments', 'complaints', 'gate_passes', 'meter_readings', 'mess_menu'],
};

/**
 * Categories each filter searches. Overdue returns the overdue invoices and
 * the active tenants who owe on them (with Call / WhatsApp), as before.
 */
export const FILTER_CATEGORIES: Record<SearchFilter, readonly SearchCategory[]> = {
  overdue: ['tenants', 'invoices'],
  drafts: ['invoices'],
  vacant: ['rooms'],
  checked_out: ['tenants'],
};

export const FILTERS_BY_ROLE: Record<SearchRole, readonly SearchFilter[]> = {
  owner: SEARCH_FILTERS,
  admin: SEARCH_FILTERS,
  manager: SEARCH_FILTERS,
  staff: ['vacant', 'checked_out'],
  tenant: [],
};

/** One search result as sent to the app. Never a database row. */
export interface SearchHit {
  category: SearchCategory;
  id: string;
  title: string;
  subtitle: string | null;
  status: string | null;
  propertyId: string;
  propertyName: string | null;
  propertyType: string | null;
  nodeId?: string | null;
  levelName?: string | null;
  invoiceId?: string | null;
  phone?: string | null;
  amount?: number | null;
  date?: string | null;
}

const BASE_FIELDS = [
  'category', 'id', 'title', 'subtitle', 'status',
  'propertyId', 'propertyName', 'propertyType', 'nodeId', 'levelName', 'invoiceId', 'date',
] as const;

/**
 * Optional fields each role may receive. Staff never get phone numbers or
 * money; tenants get amounts only on their own bills and payments.
 */
export const HIT_FIELDS_BY_ROLE: Record<SearchRole, readonly (keyof SearchHit)[]> = {
  owner: [...BASE_FIELDS, 'phone', 'amount'],
  admin: [...BASE_FIELDS, 'phone', 'amount'],
  manager: [...BASE_FIELDS, 'phone', 'amount'],
  staff: BASE_FIELDS,
  tenant: [...BASE_FIELDS, 'amount'],
};

export function serializeHit(hit: SearchHit, role: SearchRole): SearchHit {
  const out: Record<string, unknown> = {};
  for (const key of HIT_FIELDS_BY_ROLE[role]) {
    if (hit[key] !== undefined) out[key] = hit[key];
  }
  return out as unknown as SearchHit;
}

export function isSearchRole(role: unknown): role is SearchRole {
  return role === 'owner' || role === 'admin' || role === 'manager' || role === 'staff' || role === 'tenant';
}

export type SearchErrorCode =
  | 'search_query_too_short'
  | 'invalid_search_query'
  | 'invalid_search_category'
  | 'invalid_search_filter'
  | 'invalid_search_limit'
  | 'search_category_forbidden'
  | 'search_filter_forbidden'
  | 'search_not_available'
  | 'search_timeout';

/** A refused or failed search with a stable, client-safe code. */
export class SearchRequestError extends Error {
  constructor(
    readonly status: 400 | 403 | 503,
    readonly code: SearchErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'SearchRequestError';
  }
}
