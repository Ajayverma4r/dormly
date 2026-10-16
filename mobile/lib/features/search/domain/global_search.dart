// features/search/domain/global_search.dart
//
// Server-backed global search (GET /v1/search): categories and quick filters
// per role, the result model, grouping, and which screen each result opens.
// The server decides what each role may see; these lists only shape the UI.
// Pure Dart so it can be tested without Flutter.

import '../../properties/domain/property_archetype.dart';

const minSearchQueryLength = 2;

enum SearchQuickFilter { overdue, drafts, vacant, checkedOut }

extension SearchQuickFilterLabel on SearchQuickFilter {
  String get label => switch (this) {
        SearchQuickFilter.overdue => 'Overdue',
        SearchQuickFilter.drafts => 'Drafts to review',
        SearchQuickFilter.vacant => 'Vacant',
        SearchQuickFilter.checkedOut => 'Checked-out',
      };

  String get wire => switch (this) {
        SearchQuickFilter.overdue => 'overdue',
        SearchQuickFilter.drafts => 'drafts',
        SearchQuickFilter.vacant => 'vacant',
        SearchQuickFilter.checkedOut => 'checked_out',
      };
}

enum SearchCategory {
  properties,
  rooms,
  tenants,
  team,
  complaints,
  gatePasses,
  invoices,
  payments,
  meterReadings,
  messMenu,
}

extension SearchCategoryWire on SearchCategory {
  String get wire => switch (this) {
        SearchCategory.gatePasses => 'gate_passes',
        SearchCategory.meterReadings => 'meter_readings',
        SearchCategory.messMenu => 'mess_menu',
        _ => name,
      };
}

SearchCategory? searchCategoryFromWire(Object? raw) {
  final value = raw?.toString();
  for (final c in SearchCategory.values) {
    if (c.wire == value) return c;
  }
  return null;
}

bool isTenantRole(String? role) => role == 'tenant';
bool isTeamRole(String? role) =>
    const {'owner', 'admin', 'manager', 'staff'}.contains(role);
bool canSeeBilling(String? role) =>
    const {'owner', 'admin', 'manager'}.contains(role);

const _ownerCategories = [
  SearchCategory.properties,
  SearchCategory.rooms,
  SearchCategory.tenants,
  SearchCategory.team,
  SearchCategory.complaints,
  SearchCategory.gatePasses,
  SearchCategory.invoices,
  SearchCategory.payments,
  SearchCategory.meterReadings,
  SearchCategory.messMenu,
];

/// Mirrors backend search.policy.ts CATEGORIES_BY_ROLE.
List<SearchCategory> searchCategoriesForRole(String? role) => switch (role) {
      'owner' || 'admin' => _ownerCategories,
      'manager' => const [
          SearchCategory.rooms,
          SearchCategory.tenants,
          SearchCategory.complaints,
          SearchCategory.gatePasses,
          SearchCategory.invoices,
          SearchCategory.payments,
          SearchCategory.meterReadings,
          SearchCategory.messMenu,
        ],
      'staff' => const [
          SearchCategory.rooms,
          SearchCategory.tenants,
          SearchCategory.complaints,
          SearchCategory.gatePasses,
          SearchCategory.meterReadings,
          SearchCategory.messMenu,
        ],
      'tenant' => const [
          SearchCategory.rooms,
          SearchCategory.invoices,
          SearchCategory.payments,
          SearchCategory.complaints,
          SearchCategory.gatePasses,
          SearchCategory.meterReadings,
          SearchCategory.messMenu,
        ],
      _ => const [],
    };

/// Mirrors backend search.policy.ts FILTERS_BY_ROLE.
List<SearchQuickFilter> searchFiltersForRole(String? role) {
  if (canSeeBilling(role)) return SearchQuickFilter.values;
  if (role == 'staff') {
    return const [SearchQuickFilter.vacant, SearchQuickFilter.checkedOut];
  }
  return const [];
}

String searchCategoryLabel(
  SearchCategory category, {
  required bool tenant,
  String roomsLabel = 'Rooms',
}) {
  if (tenant) {
    return switch (category) {
      SearchCategory.rooms => 'My room',
      SearchCategory.invoices => 'My bills',
      SearchCategory.payments => 'My payments',
      SearchCategory.complaints => 'My complaints',
      SearchCategory.gatePasses => 'Gate passes',
      SearchCategory.meterReadings => 'Meter readings',
      SearchCategory.messMenu => 'Mess menu',
      _ => category.wire,
    };
  }
  return switch (category) {
    SearchCategory.properties => 'Properties',
    SearchCategory.rooms => roomsLabel,
    SearchCategory.tenants => 'Tenants',
    SearchCategory.team => 'Team',
    SearchCategory.complaints => 'Complaints',
    SearchCategory.gatePasses => 'Gate passes',
    SearchCategory.invoices => 'Invoices',
    SearchCategory.payments => 'Payments',
    SearchCategory.meterReadings => 'Meter readings',
    SearchCategory.messMenu => 'Mess menu',
  };
}

String searchHint({required String? role, String roomsLabel = 'Rooms'}) {
  if (isTenantRole(role)) return 'Search your bills, complaints, passes…';
  if (role == 'staff') {
    return 'Search ${roomsLabel.toLowerCase()}, tenants, complaints…';
  }
  return 'Search tenants, ${roomsLabel.toLowerCase()}, invoices…';
}

String searchHelpText(String? role) {
  if (isTenantRole(role)) {
    return 'Search your bills by month ("Nov"), payments by method ("UPI"), '
        'complaints, gate passes or the mess menu.';
  }
  if (role == 'staff') {
    return 'Search by tenant name, room or flat number, complaint ticket, '
        'visitor name or a dish on the mess menu.';
  }
  return 'Search by name, phone, room or flat number, month ("Nov"), '
      'invoice status ("overdue", "draft") or complaint ticket.';
}

/// One result from GET /v1/search. Optional fields are only sent to roles
/// allowed to see them (no phone or amount for staff, for example).
class SearchHit {
  final SearchCategory category;
  final String id;
  final String title;
  final String? subtitle;
  final String? status;
  final String propertyId;
  final String? propertyName;
  final String? propertyType;
  final String? nodeId;
  final String? levelName;
  final String? invoiceId;
  final String? phone;
  final double? amount;
  final String? date;

  const SearchHit({
    required this.category,
    required this.id,
    required this.title,
    required this.propertyId,
    this.subtitle,
    this.status,
    this.propertyName,
    this.propertyType,
    this.nodeId,
    this.levelName,
    this.invoiceId,
    this.phone,
    this.amount,
    this.date,
  });

  static String? _str(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  /// Null when the category is unknown (newer server) or the id is missing.
  static SearchHit? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final category = searchCategoryFromWire(raw['category']);
    final id = _str(raw['id']);
    if (category == null || id == null) return null;
    final amount = raw['amount'];
    return SearchHit(
      category: category,
      id: id,
      title: _str(raw['title']) ?? '',
      subtitle: _str(raw['subtitle']),
      status: _str(raw['status']),
      propertyId: _str(raw['propertyId']) ?? '',
      propertyName: _str(raw['propertyName']),
      propertyType: _str(raw['propertyType']),
      nodeId: _str(raw['nodeId']),
      levelName: _str(raw['levelName']),
      invoiceId: _str(raw['invoiceId']),
      phone: _str(raw['phone']),
      amount: amount is num ? amount.toDouble() : double.tryParse('${amount ?? ''}'),
      date: _str(raw['date']),
    );
  }
}

class SearchResponse {
  final List<SearchCategory> categories;
  final List<SearchHit> results;

  const SearchResponse({this.categories = const [], this.results = const []});

  factory SearchResponse.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    final categories = (map['categories'] as List? ?? const [])
        .map(searchCategoryFromWire)
        .whereType<SearchCategory>()
        .toList();
    final results = (map['results'] as List? ?? const [])
        .map(SearchHit.tryParse)
        .whereType<SearchHit>()
        .toList();
    return SearchResponse(categories: categories, results: results);
  }
}

/// Results grouped by category, in [order] (the role's category order).
List<(SearchCategory, List<SearchHit>)> groupSearchHits(
  List<SearchHit> hits,
  List<SearchCategory> order,
) {
  final groups = <SearchCategory, List<SearchHit>>{};
  for (final hit in hits) {
    groups.putIfAbsent(hit.category, () => []).add(hit);
  }
  final ordered = [
    ...order.where(groups.containsKey),
    ...groups.keys.where((c) => !order.contains(c)),
  ];
  return [for (final c in ordered) (c, groups[c]!)];
}

enum SearchDestinationKind {
  property,
  nodeDetail,
  rentalSpaceDetail,
  staffRooms,
  tenantProfile,
  staffTenants,
  teamList,
  teamComplaint,
  tenantComplaint,
  teamGatePasses,
  tenantGatePasses,
  invoiceDetail,
  teamMeterReadings,
  tenantMeterReadings,
  teamMessMenu,
  tenantMessMenu,
  tenantPayments,
  tenantHome,
}

/// The existing screen a result opens, with the ids it needs.
class SearchDestination {
  final SearchDestinationKind kind;
  final String propertyId;
  final String? targetId;
  final String? label;
  final String? levelName;

  const SearchDestination(
    this.kind, {
    required this.propertyId,
    this.targetId,
    this.label,
    this.levelName,
  });
}

/// Where [hit] opens for [role]. Ids come from the server result; the
/// destination screens re-check access through their own APIs.
SearchDestination? searchDestinationFor(SearchHit hit, String? role) {
  final p = hit.propertyId;
  if (isTenantRole(role)) {
    return switch (hit.category) {
      SearchCategory.rooms =>
        SearchDestination(SearchDestinationKind.tenantHome, propertyId: p),
      SearchCategory.invoices || SearchCategory.payments =>
        SearchDestination(SearchDestinationKind.tenantPayments, propertyId: p),
      SearchCategory.complaints => SearchDestination(
          SearchDestinationKind.tenantComplaint,
          propertyId: p,
          targetId: hit.id),
      SearchCategory.gatePasses =>
        SearchDestination(SearchDestinationKind.tenantGatePasses, propertyId: p),
      SearchCategory.meterReadings => SearchDestination(
          SearchDestinationKind.tenantMeterReadings,
          propertyId: p),
      SearchCategory.messMenu =>
        SearchDestination(SearchDestinationKind.tenantMessMenu, propertyId: p),
      _ => null,
    };
  }
  if (!isTeamRole(role)) return null;
  final staff = role == 'staff';
  switch (hit.category) {
    case SearchCategory.properties:
      if (!const {'owner', 'admin'}.contains(role)) return null;
      return SearchDestination(SearchDestinationKind.property,
          propertyId: hit.id, label: hit.title);
    case SearchCategory.rooms:
      if (staff) {
        return SearchDestination(SearchDestinationKind.staffRooms, propertyId: p);
      }
      final rental = propertyArchetypeFromKey(hit.propertyType) ==
          PropertyArchetype.individualLease;
      return SearchDestination(
        rental
            ? SearchDestinationKind.rentalSpaceDetail
            : SearchDestinationKind.nodeDetail,
        propertyId: p,
        targetId: hit.nodeId ?? hit.id,
        label: hit.title,
        levelName: hit.levelName ?? 'Room',
      );
    case SearchCategory.tenants:
      if (staff) {
        return SearchDestination(SearchDestinationKind.staffTenants, propertyId: p);
      }
      return SearchDestination(SearchDestinationKind.tenantProfile,
          propertyId: p, targetId: hit.id);
    case SearchCategory.team:
      if (!const {'owner', 'admin'}.contains(role)) return null;
      return SearchDestination(SearchDestinationKind.teamList, propertyId: p);
    case SearchCategory.complaints:
      return SearchDestination(SearchDestinationKind.teamComplaint,
          propertyId: p, targetId: hit.id, label: hit.propertyName);
    case SearchCategory.gatePasses:
      return SearchDestination(SearchDestinationKind.teamGatePasses, propertyId: p);
    case SearchCategory.invoices:
    case SearchCategory.payments:
      if (staff) return null;
      final invoiceId = hit.invoiceId ?? hit.id;
      return SearchDestination(SearchDestinationKind.invoiceDetail,
          propertyId: p, targetId: invoiceId);
    case SearchCategory.meterReadings:
      return SearchDestination(SearchDestinationKind.teamMeterReadings,
          propertyId: p);
    case SearchCategory.messMenu:
      return SearchDestination(SearchDestinationKind.teamMessMenu, propertyId: p);
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
