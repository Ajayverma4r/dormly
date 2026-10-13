import 'package:dormly/features/billing/domain/invoice_form_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _response({
  String start = '2026-09-01',
  String end = '2026-09-30',
  String due = '2026-10-18',
  String standardDue = '2026-10-06',
  bool late = true,
  List<Map<String, String>> unbilled = const [
    {'periodStart': '2026-09-01', 'periodEnd': '2026-09-30'},
  ],
  Map<String, dynamic>? draft,
}) =>
    {
      'today': '2026-10-13',
      'cycle': {
        'periodStart': start,
        'periodEnd': end,
        'billDate': '2026-10-01',
        'dueDate': due,
        'standardDueDate': standardDue,
        'isLate': late,
        'unbilled': unbilled,
        'gap': null,
      },
      'draft': draft,
    };

void main() {
  test('move-in 1 Sep billed on 13 Oct: Sep period with late due date', () {
    final c = InvoiceFormCycle.fromResponse(_response())!;
    expect(c.periodStart, DateTime(2026, 9, 1));
    expect(c.periodEnd, DateTime(2026, 9, 30));
    expect(c.dueDate, DateTime(2026, 10, 18));
    expect(c.isLate, isTrue);
    expect(c.lateDueNote, 'Billed late: due 18 Oct (usual date 6 Oct has passed).');
    expect(c.unbilledSummary, isNull);
    expect(c.draftNote, isNull);
  });

  test('dates are calendar dates, never shifted by the device time zone', () {
    final c = InvoiceFormCycle.fromResponse(_response(start: '2026-10-01', end: '2026-10-31'))!;
    expect([c.periodStart.day, c.periodEnd.day], [1, 31]);
  });

  test('several unbilled months are summarised oldest first', () {
    final c = InvoiceFormCycle.fromResponse(_response(
      start: '2026-08-01',
      end: '2026-08-31',
      unbilled: const [
        {'periodStart': '2026-08-01', 'periodEnd': '2026-08-31'},
        {'periodStart': '2026-09-01', 'periodEnd': '2026-09-30'},
      ],
    ))!;
    expect(c.unbilledSummary, '2 months not yet billed (Aug, Sep). Billing the oldest first.');
  });

  test('running stay on time: no notes', () {
    final c = InvoiceFormCycle.fromResponse(_response(
      start: '2026-10-01',
      end: '2026-10-31',
      due: '2026-11-06',
      standardDue: '2026-11-06',
      late: false,
      unbilled: const [],
    ))!;
    expect([c.lateDueNote, c.unbilledSummary, c.draftNote], [null, null, null]);
  });

  test('pending draft is surfaced for review', () {
    final c = InvoiceFormCycle.fromResponse(_response(
      draft: {'id': 'inv-1', 'periodStart': '2026-09-01', 'periodEnd': '2026-09-30'},
    ))!;
    expect(c.draftId, 'inv-1');
    expect(c.draftNote, 'A draft for 1 Sep – 30 Sep is waiting for review.');
  });

  test('no cycle (tenant without move-in date) or malformed dates → null', () {
    expect(InvoiceFormCycle.fromResponse({'today': '2026-10-13', 'cycle': null}), isNull);
    expect(InvoiceFormCycle.fromResponse(_response(start: 'not-a-date')), isNull);
  });
}
