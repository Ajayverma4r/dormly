import 'package:dormly/features/billing/presentation/billing_invoice_helpers.dart';
import 'package:dormly/features/tenancies/presentation/tenant_profile_screen.dart'
    show tenancyLedgerTotals;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _inv({
  required String id,
  required String total,
  String paid = '0',
  String status = 'pending',
  String due = '2026-11-20',
  Object? sentAt = '2026-11-01T10:00:00Z',
  Object? isOverdue,
}) =>
    {
      'id': id,
      'tenancy_id': 't1',
      'total_amount': total,
      'paid_amount': paid,
      'status': status,
      'due_date': due,
      'sent_at': sentAt,
      if (isOverdue != null) 'is_overdue': isOverdue,
    };

final _draft = _inv(id: 'draft', total: '6000', due: '2026-11-01', sentAt: null);
final _sentUnpaid = _inv(id: 'sent', total: '5000');
final _partial = _inv(id: 'partial', total: '5000', paid: '2000', status: 'partial');
final _paid = _inv(id: 'paid', total: '4000', paid: '4000', status: 'paid', due: '2026-10-01');
final _overdueUnpaid = _inv(
  id: 'overdue',
  total: '3000',
  status: 'overdue',
  due: '2026-11-10',
  isOverdue: true,
);
// Stored status stays 'partial'; the backend's derived flag says overdue.
final _overduePartial = _inv(
  id: 'overdue-partial',
  total: '3000',
  paid: '1000',
  status: 'partial',
  due: '2026-11-15',
  isOverdue: true,
);

void main() {
  group('isOpenUnpaidInvoice (outstanding)', () {
    test('draft is never outstanding even with a balance', () {
      expect(isDraftInvoice(_draft), isTrue);
      expect(isOpenUnpaidInvoice(_draft), isFalse);
    });

    test('sent unpaid and partially paid are outstanding', () {
      expect(isOpenUnpaidInvoice(_sentUnpaid), isTrue);
      expect(isOpenUnpaidInvoice(_partial), isTrue);
    });

    test('fully paid is not outstanding', () {
      expect(isOpenUnpaidInvoice(_paid), isFalse);
    });

    test('responses without sent_at are treated as sent', () {
      final legacy = Map<String, dynamic>.from(_sentUnpaid)..remove('sent_at');
      expect(isOpenUnpaidInvoice(legacy), isTrue);
    });
  });

  group('invoiceRemaining', () {
    test('partially paid shows the remaining balance', () {
      expect(invoiceRemaining(_partial), 3000);
    });

    test('overpaid clamps to zero', () {
      expect(invoiceRemaining(_inv(id: 'x', total: '100', paid: '150')), 0);
    });
  });

  group('outstandingTotal', () {
    test('sums sent balances only; drafts and paid excluded', () {
      final total = outstandingTotal([
        _draft,
        _sentUnpaid,
        _partial,
        _paid,
        _overdueUnpaid,
        _overduePartial,
      ]);
      expect(total, 5000 + 3000 + 3000 + 2000);
    });

    test('only drafts gives zero dues', () {
      expect(outstandingTotal([_draft]), 0);
    });
  });

  group('isOverdueInvoice (backend property-local flag)', () {
    test('unpaid flagged overdue counts', () {
      expect(isOverdueInvoice(_overdueUnpaid), isTrue);
    });

    test('partially paid flagged overdue counts despite partial status', () {
      expect(isOverdueInvoice(_overduePartial), isTrue);
    });

    test('due today in the property is not overdue, even if the date looks past',
        () {
      // Phone may be past midnight already; the property is still on the due day.
      final dueToday = _inv(
        id: 'today',
        total: '1000',
        paid: '200',
        status: 'partial',
        due: '2020-01-01',
        isOverdue: false,
      );
      expect(isOverdueInvoice(dueToday), isFalse);
    });

    test('device date is never consulted: past due date without flag or status',
        () {
      final legacy = _inv(id: 'legacy', total: '1000', due: '2020-01-01');
      expect(isOverdueInvoice(legacy), isFalse);
    });

    test('older responses fall back to the stored overdue status', () {
      final legacy = _inv(id: 'legacy', total: '1000', status: 'overdue');
      expect(isOverdueInvoice(legacy), isTrue);
    });

    test('string flag from JSON is understood', () {
      final s = _inv(id: 's', total: '1000', isOverdue: 'true');
      expect(isOverdueInvoice(s), isTrue);
    });

    test('future due date is not overdue', () {
      expect(isOverdueInvoice(_sentUnpaid), isFalse);
    });

    test('draft is never overdue, whatever the flag says', () {
      final flagged = Map<String, dynamic>.from(_draft)..['is_overdue'] = true;
      expect(isOverdueInvoice(flagged), isFalse);
    });

    test('fully paid is never overdue', () {
      final flagged = Map<String, dynamic>.from(_paid)..['is_overdue'] = true;
      expect(isOverdueInvoice(flagged), isFalse);
    });
  });

  group('invoiceDueDate', () {
    test('plain SQL date keeps its calendar day', () {
      expect(invoiceDueDate({'due_date': '2026-11-15'}), DateTime(2026, 11, 15));
    });

    test('UTC-midnight timestamp keeps its calendar day', () {
      expect(
        invoiceDueDate({'due_date': '2026-11-15T00:00:00.000Z'}),
        DateTime(2026, 11, 15),
      );
    });

    test('missing due date is null', () {
      expect(invoiceDueDate({'due_date': null}), isNull);
    });
  });

  group('tenancyLedgerTotals', () {
    test('drafts excluded from billed, outstanding and next due', () {
      final totals = tenancyLedgerTotals([_draft, _partial, _paid]);
      expect(totals.billed, 5000 + 4000);
      expect(totals.paid, 2000 + 4000);
      expect(totals.outstanding, 3000);
      expect(totals.nextDue, DateTime(2026, 11, 20));
    });

    test('only a draft shows nothing owed', () {
      final totals = tenancyLedgerTotals([_draft]);
      expect(totals.billed, 0);
      expect(totals.outstanding, 0);
      expect(totals.nextDue, isNull);
    });

    test('fully paid shows zero outstanding and no next due', () {
      final totals = tenancyLedgerTotals([_paid]);
      expect(totals.outstanding, 0);
      expect(totals.nextDue, isNull);
    });
  });

  group('draftTotal', () {
    test('an unsent draft is not outstanding but is reported as a draft', () {
      expect(outstandingTotal([_draft]), 0);
      expect(draftTotal([_draft]), 6000);
      expect(draftTotal([_draft, _sentUnpaid, _paid]), 6000);
    });
  });

  group('invoiceCalendarDate (SQL DATE from the API)', () {
    // How node-postgres serialises a DATE: the server's local midnight in UTC.
    // From a server in India, 1 Sep becomes '2026-08-31T18:30:00.000Z'.
    String serverLocalMidnight(int y, int m, int d) =>
        DateTime(y, m, d).toUtc().toIso8601String();

    test('server-local midnight keeps the real day (not the UTC prefix)', () {
      expect(invoiceCalendarDate(serverLocalMidnight(2026, 9, 1)), DateTime(2026, 9, 1));
      expect(invoiceCalendarDate(serverLocalMidnight(2026, 10, 6)), DateTime(2026, 10, 6));
    });

    test('UTC-midnight (server in UTC) and plain dates keep their day', () {
      expect(invoiceCalendarDate('2026-09-01T00:00:00.000Z'), DateTime(2026, 9, 1));
      expect(invoiceCalendarDate('2026-09-01'), DateTime(2026, 9, 1));
      expect(invoiceCalendarDate(null), isNull);
      expect(invoiceCalendarDate('nope'), isNull);
    });

    test('ledger month and due date of a Sep draft are September and 6 Oct', () {
      final inv = {
        'period_start': serverLocalMidnight(2026, 9, 1),
        'due_date': serverLocalMidnight(2026, 10, 6),
        'sent_at': null,
      };
      expect(invoiceMonthDate(inv), DateTime(2026, 9, 1));
      expect(invoiceDueDate(inv), DateTime(2026, 10, 6));
      expect(periodLabel(inv), 'Sep 2026');
    });
  });
}
