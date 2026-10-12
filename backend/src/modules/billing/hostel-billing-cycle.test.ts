import { describe, expect, it } from 'vitest';
import {
  addCalendarDays,
  addCalendarMonths,
  formatYmd,
  hostelCycleForInvoiceForm,
  hostelCyclesDue,
  isHostelPropertyType,
  parseYmd,
} from './hostel-billing-cycle';

describe('billing cycle', () => {
  it('treats only hostel/pg keys as hostel', () => {
    expect(isHostelPropertyType('hostel_pg')).toBe(true);
    expect(isHostelPropertyType('PG')).toBe(true);
    expect(isHostelPropertyType('rental_house')).toBe(false);
    expect(isHostelPropertyType('apartment')).toBe(false);
  });

  it('move-in 10 Oct: stay 10 Oct–9 Nov, bill 10 Nov, due 15 Nov', () => {
    const cycles = hostelCyclesDue('2026-10-10', '2026-11-10');
    expect(cycles).toEqual([
      {
        periodStart: '2026-10-10',
        periodEnd: '2026-11-09',
        billDate: '2026-11-10',
        dueDate: '2026-11-15',
      },
    ]);
  });

  it('nothing is billed before the anniversary (9 Nov)', () => {
    expect(hostelCyclesDue('2026-10-10', '2026-11-09')).toEqual([]);
  });

  it('recurs on 10 Dec and 10 Jan with due on the 15th', () => {
    const cycles = hostelCyclesDue('2026-10-10', '2027-01-10');
    expect(cycles.map((c) => [c.periodStart, c.billDate, c.dueDate])).toEqual([
      ['2026-10-10', '2026-11-10', '2026-11-15'],
      ['2026-11-10', '2026-12-10', '2026-12-15'],
      ['2026-12-10', '2027-01-10', '2027-01-15'],
    ]);
  });

  describe('invoice form before, on and after the anniversary', () => {
    it('before (5 Nov): shows the in-progress stay', () => {
      expect(hostelCycleForInvoiceForm('2026-10-10', '2026-11-05')).toMatchObject({
        periodStart: '2026-10-10',
        periodEnd: '2026-11-09',
        dueDate: '2026-11-15',
      });
    });
    it('on (10 Nov): shows the stay that just completed', () => {
      expect(hostelCycleForInvoiceForm('2026-10-10', '2026-11-10')).toMatchObject({
        periodStart: '2026-10-10',
        dueDate: '2026-11-15',
      });
    });
    it('after (11 Nov): moves to the next stay', () => {
      expect(hostelCycleForInvoiceForm('2026-10-10', '2026-11-11')).toMatchObject({
        periodStart: '2026-11-10',
        periodEnd: '2026-12-09',
        dueDate: '2026-12-15',
      });
    });
  });

  it('month-end move-in (31 Jan) clamps to short months without drifting', () => {
    const cycles = hostelCyclesDue('2027-01-31', '2027-05-31');
    expect(cycles.map((c) => [c.periodStart, c.periodEnd, c.billDate])).toEqual([
      ['2027-01-31', '2027-02-27', '2027-02-28'],
      ['2027-02-28', '2027-03-30', '2027-03-31'],
      ['2027-03-31', '2027-04-29', '2027-04-30'],
      ['2027-04-30', '2027-05-30', '2027-05-31'],
    ]);
  });

  it('29 Jan move-in uses 29 Feb in a leap year', () => {
    expect(hostelCyclesDue('2028-01-29', '2028-02-29')[0]).toMatchObject({
      billDate: '2028-02-29',
      dueDate: '2028-03-05',
    });
  });

  it('uses calendar months, not 30-day steps', () => {
    expect(formatYmd(addCalendarMonths(parseYmd('2026-01-31'), 1))).toBe(
      '2026-02-28',
    );
    expect(formatYmd(addCalendarDays(parseYmd('2026-11-10'), 5))).toBe(
      '2026-11-15',
    );
  });
});
