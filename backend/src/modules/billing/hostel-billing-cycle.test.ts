import { describe, expect, it, vi } from 'vitest';

vi.mock('@config/db', () => ({
  query: async () => {
    throw new Error('database must not be used by hostel-billing-cycle tests');
  },
}));

import { clockFor } from './billing-metrics';
import {
  addCalendarDays,
  addCalendarMonths,
  calendarDateInTimeZone,
  checkMoveInEdit,
  DEFAULT_PROPERTY_TIME_ZONE,
  formatYmd,
  hostelBillingTimeZone,
  planHostelCycles,
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

  it('move-in 1 Sep: period 1–30 Sep, generated 1 Oct, due 6 Oct', () => {
    expect(hostelCyclesDue('2026-09-01', '2026-10-01')).toEqual([
      {
        periodStart: '2026-09-01',
        periodEnd: '2026-09-30',
        billDate: '2026-10-01',
        dueDate: '2026-10-06',
      },
    ]);
    expect(hostelCyclesDue('2026-09-01', '2026-09-30')).toEqual([]);
  });

  it('move-in 10 Sep: period 10 Sep–9 Oct, generated 10 Oct, due 15 Oct', () => {
    expect(hostelCyclesDue('2026-09-10', '2026-10-10')).toEqual([
      {
        periodStart: '2026-09-10',
        periodEnd: '2026-10-09',
        billDate: '2026-10-10',
        dueDate: '2026-10-15',
      },
    ]);
  });

  it('due date crosses month and year ends by calendar days', () => {
    expect(hostelCyclesDue('2026-11-28', '2026-12-28')[0].dueDate).toBe('2027-01-02');
    expect(hostelCyclesDue('2027-01-28', '2027-02-28')[0].dueDate).toBe('2027-03-05');
    expect(hostelCyclesDue('2028-01-28', '2028-02-28')[0].dueDate).toBe('2028-03-04');
  });

  it('29 Feb move-in (leap year) clamps to 28 Feb next year, then returns to the 29th', () => {
    const cycles = hostelCyclesDue('2028-02-29', '2029-03-29');
    expect(cycles[0]).toMatchObject({
      periodStart: '2028-02-29',
      periodEnd: '2028-03-28',
      billDate: '2028-03-29',
    });
    expect(cycles.slice(-3).map((c) => [c.periodStart, c.periodEnd, c.billDate])).toEqual([
      ['2028-12-29', '2029-01-28', '2029-01-29'],
      ['2029-01-29', '2029-02-27', '2029-02-28'],
      ['2029-02-28', '2029-03-28', '2029-03-29'],
    ]);
  });

  it('30th and 31st move-ins never drift after February', () => {
    const thirty = hostelCyclesDue('2027-01-30', '2027-04-30');
    expect(thirty.map((c) => c.billDate)).toEqual(['2027-02-28', '2027-03-30', '2027-04-30']);
    const thirtyOne = hostelCyclesDue('2026-12-31', '2027-03-31');
    expect(thirtyOne.map((c) => c.billDate)).toEqual(['2027-01-31', '2027-02-28', '2027-03-31']);
  });

  it('consecutive periods are contiguous: no gaps or overlaps', () => {
    for (const checkIn of ['2026-01-31', '2028-02-29', '2026-09-10', '2026-03-30']) {
      const cycles = hostelCyclesDue(checkIn, '2029-12-31');
      for (let i = 1; i < cycles.length; i += 1) {
        expect(cycles[i].periodStart).toBe(cycles[i - 1].billDate);
        expect(
          formatYmd(addCalendarDays(parseYmd(cycles[i - 1].periodEnd), 1)),
        ).toBe(cycles[i].periodStart);
      }
    }
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

describe('planHostelCycles', () => {
  const sep = { periodStart: '2026-09-01', periodEnd: '2026-09-30' };

  it('first run bills every completed cycle (backlog)', () => {
    const plan = planHostelCycles({
      checkIn: '2026-08-01',
      today: '2026-10-12',
      moveOut: null,
      billed: [],
    });
    expect(plan.cycles.map((c) => c.periodStart)).toEqual(['2026-08-01', '2026-09-01']);
    expect(plan.gap).toBeNull();
  });

  it('a repeated run plans nothing once the cycle is billed', () => {
    const plan = planHostelCycles({
      checkIn: '2026-09-01',
      today: '2026-10-12',
      moveOut: null,
      billed: [sep],
    });
    expect(plan.cycles).toEqual([]);
  });

  it('continues with the next contiguous cycle', () => {
    const plan = planHostelCycles({
      checkIn: '2026-09-01',
      today: '2026-11-01',
      moveOut: null,
      billed: [sep],
    });
    expect(plan.cycles.map((c) => [c.periodStart, c.periodEnd])).toEqual([
      ['2026-10-01', '2026-10-31'],
    ]);
    expect(plan.gap).toBeNull();
  });

  it('move-in moved later (1 Sep → 10 Sep): no overlap with the billed 1–30 Sep, gap reported', () => {
    const plan = planHostelCycles({
      checkIn: '2026-09-10',
      today: '2026-11-10',
      moveOut: null,
      billed: [sep],
    });
    // 10 Sep–9 Oct overlaps the billed September invoice and is skipped.
    expect(plan.cycles.map((c) => [c.periodStart, c.periodEnd])).toEqual([
      ['2026-10-10', '2026-11-09'],
    ]);
    expect(plan.gap).toEqual({ from: '2026-10-01', to: '2026-10-09' });
  });

  it('move-in moved earlier (10 Sep → 1 Sep): no retroactive or overlapping cycles', () => {
    const plan = planHostelCycles({
      checkIn: '2026-09-01',
      today: '2026-11-01',
      moveOut: null,
      billed: [{ periodStart: '2026-09-10', periodEnd: '2026-10-09' }],
    });
    // 1–30 Sep and 1–31 Oct both start on or before 9 Oct.
    expect(plan.cycles).toEqual([]);

    const later = planHostelCycles({
      checkIn: '2026-09-01',
      today: '2026-12-01',
      moveOut: null,
      billed: [{ periodStart: '2026-09-10', periodEnd: '2026-10-09' }],
    });
    expect(later.cycles.map((c) => c.periodStart)).toEqual(['2026-11-01']);
    expect(later.gap).toEqual({ from: '2026-10-10', to: '2026-10-31' });
  });

  it('an edit that keeps the same anniversary day changes nothing', () => {
    const plan = planHostelCycles({
      checkIn: '2026-08-01',
      today: '2026-10-12',
      moveOut: null,
      billed: [sep],
    });
    // August is before the last billed period, so it is not back-billed.
    expect(plan.cycles).toEqual([]);
  });

  it('leaves the period after move-out to settlement', () => {
    const plan = planHostelCycles({
      checkIn: '2026-09-01',
      today: '2026-12-01',
      moveOut: '2026-10-15',
      billed: [sep],
    });
    expect(plan.cycles).toEqual([]);
  });

  it('bills a cycle whose bill date is on the move-out day', () => {
    const plan = planHostelCycles({
      checkIn: '2026-09-01',
      today: '2026-12-01',
      moveOut: '2026-11-01',
      billed: [sep],
    });
    expect(plan.cycles.map((c) => c.periodStart)).toEqual(['2026-10-01']);
  });

  it('nothing is due before the first anniversary or for a future move-in', () => {
    expect(
      planHostelCycles({ checkIn: '2026-09-15', today: '2026-10-12', moveOut: null, billed: [] })
        .cycles,
    ).toEqual([]);
    expect(
      planHostelCycles({ checkIn: '2026-12-01', today: '2026-10-12', moveOut: null, billed: [] })
        .cycles,
    ).toEqual([]);
  });
});

describe('checkMoveInEdit', () => {
  const sep1 = { periodStart: '2026-09-01', periodEnd: '2026-09-30' };
  const oct1 = { periodStart: '2026-10-01', periodEnd: '2026-10-31' };

  it('allows any change while no cycle invoice exists', () => {
    expect(
      checkMoveInEdit({ currentCheckIn: '2026-09-01', newCheckIn: '2026-09-10', billed: [] }),
    ).toEqual({ allowed: true });
  });

  it('allows re-saving the same move-in date', () => {
    expect(
      checkMoveInEdit({ currentCheckIn: '2026-09-01', newCheckIn: '2026-09-01', billed: [sep1] }),
    ).toEqual({ allowed: true });
  });

  it('blocks Phase 3 gap example 1: 1 Sep → 10 Sep after 1–30 Sep is billed', () => {
    expect(
      checkMoveInEdit({ currentCheckIn: '2026-09-01', newCheckIn: '2026-09-10', billed: [sep1] }),
    ).toEqual({
      allowed: false,
      reason: 'anniversary_changed',
      firstBilledStart: '2026-09-01',
      lastBilledEnd: '2026-09-30',
    });
  });

  it('blocks Phase 3 gap example 2: 10 Sep → 1 Sep after 10 Sep–9 Oct is billed', () => {
    expect(
      checkMoveInEdit({
        currentCheckIn: '2026-09-10',
        newCheckIn: '2026-09-01',
        billed: [{ periodStart: '2026-09-10', periodEnd: '2026-10-09' }],
      }),
    ).toMatchObject({ allowed: false, reason: 'anniversary_changed' });
  });

  it('blocks a month-end correction that changes the day (31 Jan → 30 Jan)', () => {
    expect(
      checkMoveInEdit({
        currentCheckIn: '2027-01-31',
        newCheckIn: '2027-01-30',
        billed: [{ periodStart: '2027-01-31', periodEnd: '2027-02-27' }],
      }),
    ).toMatchObject({ allowed: false, reason: 'anniversary_changed' });
  });

  it('blocks moving the date past an already-billed period start (same day: 1 Sep → 1 Nov)', () => {
    expect(
      checkMoveInEdit({ currentCheckIn: '2026-09-01', newCheckIn: '2026-11-01', billed: [sep1, oct1] }),
    ).toMatchObject({ allowed: false, reason: 'after_billed_period' });
    expect(
      checkMoveInEdit({ currentCheckIn: '2026-09-01', newCheckIn: '2026-10-01', billed: [sep1, oct1] }),
    ).toMatchObject({ allowed: false, reason: 'after_billed_period' });
  });

  it('allows an earlier date on the same anniversary day (1 Sep → 1 Aug)', () => {
    expect(
      checkMoveInEdit({ currentCheckIn: '2026-09-01', newCheckIn: '2026-08-01', billed: [sep1, oct1] }),
    ).toEqual({ allowed: true });
  });

  it('allows an earlier month-end date whose clamped cycles match (31 Jan → 31 Dec)', () => {
    expect(
      checkMoveInEdit({
        currentCheckIn: '2027-01-31',
        newCheckIn: '2026-12-31',
        billed: [
          { periodStart: '2027-01-31', periodEnd: '2027-02-27' },
          { periodStart: '2027-02-28', periodEnd: '2027-03-30' },
        ],
      }),
    ).toEqual({ allowed: true });
  });

  it('first move-in date on a tenancy with manual cycle invoices must line up with them', () => {
    expect(
      checkMoveInEdit({ currentCheckIn: null, newCheckIn: '2026-08-01', billed: [sep1, oct1] }),
    ).toEqual({ allowed: true });
    expect(
      checkMoveInEdit({ currentCheckIn: null, newCheckIn: '2026-08-10', billed: [sep1, oct1] }),
    ).toMatchObject({ allowed: false, reason: 'misaligned' });
  });

  it('blocks a same-day date whose cycles would not resume after the last billed period', () => {
    // Billed period was entered manually as 1 Sep – 15 Sep.
    expect(
      checkMoveInEdit({
        currentCheckIn: '2026-09-01',
        newCheckIn: '2026-08-01',
        billed: [{ periodStart: '2026-09-01', periodEnd: '2026-09-15' }],
      }),
    ).toMatchObject({ allowed: false, reason: 'misaligned' });
  });
});

describe('time zone', () => {
  it('uses a configured valid IANA zone as-is, UTC included', () => {
    expect(hostelBillingTimeZone('UTC')).toBe('UTC');
    expect(hostelBillingTimeZone('  UTC  ')).toBe('UTC');
    expect(hostelBillingTimeZone('Asia/Kolkata')).toBe('Asia/Kolkata');
    expect(hostelBillingTimeZone('Asia/Dubai')).toBe('Asia/Dubai');
    expect(hostelBillingTimeZone('America/New_York')).toBe('America/New_York');
  });

  it('accepts a valid zone in any letter case and keeps the configured spelling', () => {
    expect(hostelBillingTimeZone('utc')).toBe('utc');
    expect(calendarDateInTimeZone(new Date('2026-09-30T18:30:00Z'), hostelBillingTimeZone('utc'))).toBe(
      '2026-09-30',
    );
  });

  it('falls back to the documented default only when the zone is missing or invalid', () => {
    expect(DEFAULT_PROPERTY_TIME_ZONE).toBe('Asia/Kolkata');
    expect(hostelBillingTimeZone(null)).toBe('Asia/Kolkata');
    expect(hostelBillingTimeZone(undefined)).toBe('Asia/Kolkata');
    expect(hostelBillingTimeZone('')).toBe('Asia/Kolkata');
    expect(hostelBillingTimeZone('   ')).toBe('Asia/Kolkata');
    expect(hostelBillingTimeZone('Mars/Olympus_Mons')).toBe('Asia/Kolkata');
    expect(hostelBillingTimeZone('IST+5:30')).toBe('Asia/Kolkata');
  });

  it('UTC property: the day turns at UTC midnight', () => {
    expect(clockFor('UTC', new Date('2026-09-30T23:59:59Z')).today).toBe('2026-09-30');
    expect(clockFor('UTC', new Date('2026-10-01T00:00:00Z')).today).toBe('2026-10-01');
    // 18:30Z is already 1 Oct in India but still 30 Sep for a UTC property.
    expect(clockFor('UTC', new Date('2026-09-30T18:30:00Z')).today).toBe('2026-09-30');
  });

  it('Asia/Kolkata property: the day turns at 18:30Z', () => {
    expect(clockFor('Asia/Kolkata', new Date('2026-09-30T18:29:59Z')).today).toBe('2026-09-30');
    expect(clockFor('Asia/Kolkata', new Date('2026-09-30T18:30:00Z')).today).toBe('2026-10-01');
  });

  it('invalid zone uses the Asia/Kolkata calendar', () => {
    const c = clockFor('Not/AZone', new Date('2026-09-30T18:30:00Z'));
    expect(c.timeZone).toBe('Asia/Kolkata');
    expect(c.today).toBe('2026-10-01');
    expect(clockFor(null, new Date('2026-09-30T18:29:59Z')).today).toBe('2026-09-30');
  });

  it('year rollover: month bounds follow the configured zone', () => {
    const instant = new Date('2026-12-31T20:00:00Z'); // 1 Jan 01:30 IST
    expect(clockFor('UTC', instant)).toEqual({
      timeZone: 'UTC',
      today: '2026-12-31',
      monthStart: '2026-12-01',
      nextMonthStart: '2027-01-01',
    });
    expect(clockFor('Asia/Kolkata', instant)).toEqual({
      timeZone: 'Asia/Kolkata',
      today: '2027-01-01',
      monthStart: '2027-01-01',
      nextMonthStart: '2027-02-01',
    });
  });

  it('reads the check-in day in the property zone (local midnight sent as UTC)', () => {
    const pickerMidnight = new Date('2026-08-31T18:30:00Z'); // 1 Sep 00:00 IST
    expect(calendarDateInTimeZone(pickerMidnight, 'Asia/Kolkata')).toBe('2026-09-01');
  });

  it('the bill day starts at local midnight, not UTC midnight', () => {
    expect(calendarDateInTimeZone(new Date('2026-09-30T18:29:00Z'), 'Asia/Kolkata')).toBe(
      '2026-09-30',
    );
    expect(calendarDateInTimeZone(new Date('2026-09-30T18:30:00Z'), 'Asia/Kolkata')).toBe(
      '2026-10-01',
    );
  });
});

