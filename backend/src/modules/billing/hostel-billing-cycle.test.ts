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

describe('hostel billing cycle', () => {
  it('treats only hostel/pg keys as hostel', () => {
    expect(isHostelPropertyType('hostel_pg')).toBe(true);
    expect(isHostelPropertyType('PG')).toBe(true);
    expect(isHostelPropertyType('rental_house')).toBe(false);
    expect(isHostelPropertyType('apartment')).toBe(false);
  });

  it('check-in 1 Sep bills on 1 Oct due 5 Oct for the September stay', () => {
    const cycles = hostelCyclesDue('2026-09-01', '2026-10-01');
    expect(cycles).toHaveLength(1);
    expect(cycles[0]).toMatchObject({
      periodStart: '2026-09-01',
      periodEnd: '2026-09-30',
      billDate: '2026-10-01',
      dueDate: '2026-10-05',
    });
  });

  it('does not bill before the first anniversary', () => {
    expect(hostelCyclesDue('2026-09-01', '2026-09-30')).toEqual([]);
  });

  it('form before the anniversary still shows Sep stay and 5 Oct due', () => {
    expect(hostelCycleForInvoiceForm('2026-09-01', '2026-09-29')).toMatchObject({
      periodStart: '2026-09-01',
      periodEnd: '2026-09-30',
      billDate: '2026-10-01',
      dueDate: '2026-10-05',
    });
  });

  it('check-in 17 Sep: stay 17 Sep–16 Oct, bill 17 Oct, due 21 Oct', () => {
    expect(hostelCycleForInvoiceForm('2026-09-17', '2026-09-29')).toMatchObject({
      periodStart: '2026-09-17',
      periodEnd: '2026-10-16',
      billDate: '2026-10-17',
      dueDate: '2026-10-21',
    });
    const cycles = hostelCyclesDue('2026-09-17', '2026-12-17');
    expect(cycles.map((c) => [c.periodStart, c.billDate, c.dueDate])).toEqual([
      ['2026-09-17', '2026-10-17', '2026-10-21'],
      ['2026-10-17', '2026-11-17', '2026-11-21'],
      ['2026-11-17', '2026-12-17', '2026-12-21'],
    ]);
  });

  it('continues the same anniversary, not the 1st of each month', () => {
    const cycles = hostelCyclesDue('2026-09-01', '2026-12-01');
    expect(cycles.map((c) => [c.billDate, c.dueDate])).toEqual([
      ['2026-10-01', '2026-10-05'],
      ['2026-11-01', '2026-11-05'],
      ['2026-12-01', '2026-12-05'],
    ]);
  });

  it('uses calendar months, not 30-day steps (31 Jan → 28 Feb)', () => {
    expect(formatYmd(addCalendarMonths(parseYmd('2026-01-31'), 1))).toBe(
      '2026-02-28',
    );
    expect(formatYmd(addCalendarDays(parseYmd('2026-10-01'), 4))).toBe(
      '2026-10-05',
    );
  });
});
