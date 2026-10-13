import 'package:dormly/features/search/domain/global_search.dart';
import 'package:flutter_test/flutter_test.dart';

final _tenants = <Map<String, dynamic>>[
  {'id': 't1', 'full_name': 'Ravi Kumar', 'phone': '+91 98765 43210', 'node_name': '101', 'status': 'active'},
  {'id': 't2', 'full_name': 'Anita Shah', 'phone': '9123456780', 'node_name': '202', 'status': 'active'},
  {'id': 't3', 'full_name': 'Old Guest', 'phone': '9000000000', 'node_name': '303', 'status': 'ended'},
];

// `is_overdue` is the backend's property-local judgement.
final _invoices = <Map<String, dynamic>>[
  // Sent, unpaid, past due.
  {'id': 'i1', 'tenancy_id': 't1', 'full_name': 'Ravi Kumar', 'period_start': '2026-10-10', 'due_date': '2026-11-15', 'total_amount': '5000', 'paid_amount': '0', 'status': 'overdue', 'is_overdue': true, 'sent_at': '2026-11-10T10:00:00Z'},
  // Draft (not sent).
  {'id': 'i2', 'tenancy_id': 't2', 'full_name': 'Anita Shah', 'period_start': '2026-10-16', 'due_date': '2026-11-21', 'total_amount': '6000', 'paid_amount': '0', 'status': 'pending', 'is_overdue': false, 'sent_at': null},
  // Partially paid, due today in the property → not overdue.
  {'id': 'i3', 'tenancy_id': 't2', 'full_name': 'Anita Shah', 'period_start': '2026-09-16', 'due_date': '2026-11-16', 'total_amount': '6000', 'paid_amount': '2000', 'status': 'partial', 'is_overdue': false, 'sent_at': '2026-10-16T10:00:00Z'},
];

final _withPartialOverdue = [
  ..._invoices,
  // Partially paid and past due: stored status stays 'partial'.
  {'id': 'i4', 'tenancy_id': 't2', 'full_name': 'Anita Shah', 'period_start': '2026-08-16', 'due_date': '2026-09-21', 'total_amount': '6000', 'paid_amount': '1000', 'status': 'partial', 'is_overdue': true, 'sent_at': '2026-08-16T10:00:00Z'},
];

const _rooms = [
  SearchRoom(id: 'r1', name: '101', blockName: 'Floor 1', levelName: 'Room', occupied: true, tenantName: 'Ravi Kumar'),
  SearchRoom(id: 'r2', name: '104', blockName: 'Floor 1', levelName: 'Room', occupied: false),
];

GlobalSearchResults _search(String q, [SearchQuickFilter? f]) => runGlobalSearch(
      query: q,
      filter: f,
      tenants: _tenants,
      rooms: _rooms,
      invoices: _invoices,
      complaints: const [
        {'id': 'c1', 'ticket_number': 'CMP-AB12CD34', 'category': 'Plumbing', 'node_name': '101', 'status': 'open'},
      ],
    );

void main() {
  test('empty query and no filter returns nothing', () {
    expect(_search('').isEmpty, isTrue);
  });

  test('name, room and digit-only phone search', () {
    expect(_search('ravi').tenants.map((t) => t['id']), ['t1']);
    expect(_search('98765').tenants.map((t) => t['id']), ['t1']);
    expect(_search('104').rooms.map((r) => r.id), ['r2']);
  });

  test('month and status words match invoices', () {
    expect(_search('oct').invoices.map((i) => i['id']), ['i1', 'i2']);
    expect(_search('draft').invoices.map((i) => i['id']), ['i2']);
    expect(_search('overdue').invoices.map((i) => i['id']), ['i1']);
  });

  test('complaint ticket search', () {
    expect(_search('cmp-ab12').complaints.length, 1);
  });

  test('quick filters', () {
    final overdue = _search('', SearchQuickFilter.overdue);
    expect(overdue.invoices.map((i) => i['id']), ['i1']);
    expect(overdue.tenants.map((t) => t['id']), ['t1']);
    expect(_search('', SearchQuickFilter.drafts).invoices.map((i) => i['id']), ['i2']);
    expect(_search('', SearchQuickFilter.vacant).rooms.map((r) => r.id), ['r2']);
    expect(_search('', SearchQuickFilter.checkedOut).tenants.map((t) => t['id']), ['t3']);
  });

  test('partially paid overdue invoice and its tenant are found', () {
    final r = runGlobalSearch(
      query: '',
      filter: SearchQuickFilter.overdue,
      tenants: _tenants,
      invoices: _withPartialOverdue,
    );
    expect(r.invoices.map((i) => i['id']), ['i1', 'i4']);
    expect(r.tenants.map((t) => t['id']), ['t1', 't2']);
  });

  test('recent searches: newest first, de-duplicated, capped', () {
    var r = <String>[];
    for (final q in ['a1', 'b2', 'A1', 'c3']) {
      r = pushRecentSearch(r, q, max: 2);
    }
    expect(r, ['c3', 'A1']);
  });
}
