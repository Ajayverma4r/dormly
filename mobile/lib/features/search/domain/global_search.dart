// features/search/domain/global_search.dart
//
// Property-wide search over data the app already loads (tenants, rooms,
// invoices, complaints). Pure Dart so it can be tested without Flutter.

import '../../billing/presentation/billing_invoice_helpers.dart'
    show isDraftInvoice, isOpenUnpaidInvoice, isOverdueInvoice;

enum SearchQuickFilter { overdue, drafts, vacant, checkedOut }

extension SearchQuickFilterLabel on SearchQuickFilter {
  String get label => switch (this) {
        SearchQuickFilter.overdue => 'Overdue',
        SearchQuickFilter.drafts => 'Drafts to review',
        SearchQuickFilter.vacant => 'Vacant',
        SearchQuickFilter.checkedOut => 'Checked-out',
      };
}

/// Minimal room view so matching does not depend on the rooms tree widgets.
class SearchRoom {
  final String id;
  final String name;
  final String blockName;
  final String levelName;
  final bool occupied;
  final String? tenantName;

  const SearchRoom({
    required this.id,
    required this.name,
    required this.blockName,
    required this.levelName,
    required this.occupied,
    this.tenantName,
  });
}

class GlobalSearchResults {
  final List<Map<String, dynamic>> tenants;
  final List<SearchRoom> rooms;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> complaints;

  const GlobalSearchResults({
    this.tenants = const [],
    this.rooms = const [],
    this.invoices = const [],
    this.complaints = const [],
  });

  bool get isEmpty =>
      tenants.isEmpty && rooms.isEmpty && invoices.isEmpty && complaints.isEmpty;

  int get total =>
      tenants.length + rooms.length + invoices.length + complaints.length;
}

const _monthNames = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

String _s(dynamic v) => (v ?? '').toString().toLowerCase();

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Text match with digit-only phone matching ("98765" finds "+91 98765 43210").
bool _textMatches(String query, List<String> fields, {List<String> phones = const []}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  for (final f in fields) {
    if (f.contains(q)) return true;
  }
  final digits = _digits(q);
  if (digits.length >= 3 && digits.length == q.replaceAll(RegExp(r'[\s+\-]'), '').length) {
    for (final p in phones) {
      if (_digits(p).contains(digits)) return true;
    }
  }
  return false;
}

bool _tenantHasOverdue(
  Map<String, dynamic> tenant,
  List<Map<String, dynamic>> invoices,
) {
  final id = _s(tenant['id']);
  return invoices.any(
    (i) => _s(i['tenancy_id']) == id && isOverdueInvoice(i),
  );
}

/// Month words ("nov", "november") match the invoice's period-start month.
bool _invoiceMonthMatches(String q, Map<String, dynamic> inv) {
  if (q.length < 3) return false;
  final raw = (inv['period_start'] ?? inv['due_date'])?.toString() ?? '';
  if (raw.length < 7) return false;
  final month = int.tryParse(raw.substring(5, 7));
  if (month == null || month < 1 || month > 12) return false;
  return _monthNames[month - 1].startsWith(q);
}

bool _invoiceStatusWordMatches(String q, Map<String, dynamic> inv) {
  if (q.length < 3) return false;
  if ('draft'.startsWith(q) || 'review'.startsWith(q)) return isDraftInvoice(inv);
  if ('overdue'.startsWith(q)) return isOverdueInvoice(inv);
  if ('paid'.startsWith(q)) return !isDraftInvoice(inv) && _s(inv['status']) == 'paid';
  if ('partial'.startsWith(q)) return _s(inv['status']) == 'partial';
  if ('pending'.startsWith(q) || 'unpaid'.startsWith(q)) {
    return isOpenUnpaidInvoice(inv);
  }
  return false;
}

GlobalSearchResults runGlobalSearch({
  required String query,
  SearchQuickFilter? filter,
  List<Map<String, dynamic>> tenants = const [],
  List<SearchRoom> rooms = const [],
  List<Map<String, dynamic>> invoices = const [],
  List<Map<String, dynamic>> complaints = const [],
  int limitPerSection = 20,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty && filter == null) return const GlobalSearchResults();

  List<T> take<T>(Iterable<T> items) => items.take(limitPerSection).toList();

  bool tenantMatches(Map<String, dynamic> t) => _textMatches(
        q,
        [
          _s(t['full_name']),
          _s(t['user_name']),
          _s(t['node_name']),
          _s(t['floor_name']),
          _s(t['phone']),
        ],
        phones: [t['phone']?.toString() ?? ''],
      );

  bool roomMatches(SearchRoom r) => _textMatches(
        q,
        [_s(r.name), _s(r.blockName), _s(r.tenantName)],
      );

  bool invoiceMatches(Map<String, dynamic> i) =>
      _textMatches(
        q,
        [_s(i['full_name']), _s(i['node_name']), _s(i['floor_name'])],
        phones: [i['phone']?.toString() ?? ''],
      ) ||
      _invoiceMonthMatches(q, i) ||
      _invoiceStatusWordMatches(q, i);

  bool complaintMatches(Map<String, dynamic> c) => _textMatches(
        q,
        [
          _s(c['ticket_number']),
          _s(c['category']),
          _s(c['description']),
          _s(c['node_name']),
          _s(c['tenant_name']),
          _s(c['status']).replaceAll('_', ' '),
        ],
      );

  switch (filter) {
    case SearchQuickFilter.overdue:
      return GlobalSearchResults(
        tenants: take(tenants.where((t) =>
            _s(t['status']) == 'active' &&
            _tenantHasOverdue(t, invoices) &&
            tenantMatches(t))),
        invoices: take(invoices.where(
            (i) => isOverdueInvoice(i) && invoiceMatches(i))),
      );
    case SearchQuickFilter.drafts:
      return GlobalSearchResults(
        invoices: take(
            invoices.where((i) => isDraftInvoice(i) && invoiceMatches(i))),
      );
    case SearchQuickFilter.vacant:
      return GlobalSearchResults(
        rooms: take(rooms.where((r) => !r.occupied && roomMatches(r))),
      );
    case SearchQuickFilter.checkedOut:
      return GlobalSearchResults(
        tenants: take(tenants
            .where((t) => _s(t['status']) == 'ended' && tenantMatches(t))),
      );
    case null:
      return GlobalSearchResults(
        tenants: take(tenants.where(tenantMatches)),
        rooms: take(rooms.where(roomMatches)),
        invoices: take(invoices.where(invoiceMatches)),
        complaints: take(complaints.where(complaintMatches)),
      );
  }
}

/// Most-recent-first, case-insensitive de-duplication, capped.
List<String> pushRecentSearch(List<String> current, String query, {int max = 8}) {
  final q = query.trim();
  if (q.length < 2) return current;
  final next = [
    q,
    ...current.where((e) => e.toLowerCase() != q.toLowerCase()),
  ];
  return next.take(max).toList();
}
