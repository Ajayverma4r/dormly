import 'package:dormly/features/tenancies/presentation/node_detail_screen.dart'
    show activeTenancyForNode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns the active tenancy id, never the bed id', () {
    final t = activeTenancyForNode([
      {'id': 'ten-old', 'node_id': 'bed-1', 'status': 'ended'},
      {'id': 'ten-1', 'node_id': 'BED-1', 'status': 'active'},
    ], 'bed-1');
    expect(t?['id'], 'ten-1');
  });

  test('ignores tenancies on a different node', () {
    final t = activeTenancyForNode([
      {'id': 'ten-2', 'node_id': 'bed-2', 'status': 'active'},
    ], 'bed-1');
    expect(t, isNull);
  });

  test('vacant node (only ended tenancies) has no active tenancy', () {
    final t = activeTenancyForNode([
      {'id': 'ten-old', 'node_id': 'bed-1', 'status': 'ended'},
    ], 'bed-1');
    expect(t, isNull);
  });

  test('skips rows without a tenancy id', () {
    final t = activeTenancyForNode([
      {'node_id': 'bed-1', 'status': 'active'},
    ], 'bed-1');
    expect(t, isNull);
  });
}
