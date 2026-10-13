// Monthly billing cycle for every property type.
// bill date = check-in anniversary + N calendar months (not +30 days)
// default due date = bill date + DUE_DAYS_AFTER_BILL calendar days
// Owner-edited due dates live on invoices.due_date and are never rewritten here.
//
// Month-end move-ins: every anniversary is computed from the original
// check-in day and clamped to the target month's length, so 31 Jan bills on
// 28/29 Feb, 31 Mar, 30 Apr, 31 May… and never drifts to the 28th.

export const DUE_DAYS_AFTER_BILL = 5;

export type Ymd = { year: number; month: number; day: number };

export type HostelBillingCycle = {
  /** YYYY-MM-DD — check-in anniversary when the bill is created. */
  billDate: string;
  /** YYYY-MM-DD — bill date + 5 calendar days. Owner may replace this on the invoice. */
  dueDate: string;
  /** First day of the completed stay (check-in anniversary). */
  periodStart: string;
  /** Day before the next anniversary. */
  periodEnd: string;
};

export function isHostelPropertyType(raw: string | null | undefined): boolean {
  const key = (raw ?? '').trim().toLowerCase();
  return (
    key === 'hostel_pg' ||
    key === 'hostel' ||
    key === 'pg' ||
    key === 'coliving' ||
    key === 'staff_housing' ||
    key === 'hotel'
  );
}

export function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

export function formatYmd(d: Ymd): string {
  return `${d.year}-${pad2(d.month)}-${pad2(d.day)}`;
}

export function parseYmd(raw: string): Ymd {
  const [year, month, day] = raw.slice(0, 10).split('-').map(Number);
  if (!year || !month || !day) {
    throw new Error(`Invalid date: ${raw}`);
  }
  return { year, month, day };
}

export function compareYmd(a: string, b: string): number {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

/** Last calendar day of a 1-based month. */
export function lastDayOfMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

/**
 * Add calendar months, clamping the day to the target month's length
 * (31 Jan + 1 month → 28/29 Feb).
 */
export function addCalendarMonths(date: Ymd, months: number): Ymd {
  const zeroBased = date.month - 1 + months;
  const year = date.year + Math.floor(zeroBased / 12);
  const month = ((zeroBased % 12) + 12) % 12;
  const month1 = month + 1;
  const day = Math.min(date.day, lastDayOfMonth(year, month1));
  return { year, month: month1, day };
}

export function addCalendarDays(date: Ymd, days: number): Ymd {
  const utc = new Date(Date.UTC(date.year, date.month - 1, date.day));
  utc.setUTCDate(utc.getUTCDate() + days);
  return {
    year: utc.getUTCFullYear(),
    month: utc.getUTCMonth() + 1,
    day: utc.getUTCDate(),
  };
}

/**
 * One completed stay.
 * period = check-in anniversary → day before the next anniversary
 * bill date = next anniversary (period end + 1 day)
 * due date = bill date + DUE_DAYS_AFTER_BILL calendar days
 */
function cycleAt(checkIn: Ymd, index: number): HostelBillingCycle {
  const periodStartDate = addCalendarMonths(checkIn, index);
  const bill = addCalendarMonths(checkIn, index + 1);
  const billDate = formatYmd(bill);
  return {
    billDate,
    dueDate: formatYmd(addCalendarDays(bill, DUE_DAYS_AFTER_BILL)),
    periodStart: formatYmd(periodStartDate),
    periodEnd: formatYmd(addCalendarDays(bill, -1)),
  };
}

/**
 * Completed hostel cycles whose bill date is on or before [today].
 * Nothing is billed on the check-in day itself.
 */
export function hostelCyclesDue(checkInRaw: string, todayRaw: string): HostelBillingCycle[] {
  const checkIn = parseYmd(checkInRaw);
  const today = todayRaw.slice(0, 10);
  const cycles: HostelBillingCycle[] = [];

  for (let n = 0; n < 240; n += 1) {
    const cycle = cycleAt(checkIn, n);
    if (compareYmd(cycle.billDate, today) > 0) break;
    cycles.push(cycle);
  }

  return cycles;
}

export type BilledPeriod = { periodStart: string; periodEnd: string };

export type CyclePlan = {
  cycles: HostelBillingCycle[];
  /** Days between the last billed period and the first new cycle, if any. */
  gap: { from: string; to: string } | null;
};

/**
 * Cycles to draft now for one tenancy.
 * Existing cycle invoices are never rewritten. Billing resumes with the first
 * anniversary period that starts after the last billed period, so a changed
 * move-in date can never produce overlapping or duplicate periods. Cycles
 * whose bill date falls after move-out are left to move-out settlement.
 */
export function planHostelCycles(opts: {
  checkIn: string;
  today: string;
  moveOut: string | null;
  billed: BilledPeriod[];
}): CyclePlan {
  const lastBilledEnd = opts.billed.reduce<string | null>(
    (max, p) => (max == null || compareYmd(p.periodEnd, max) > 0 ? p.periodEnd : max),
    null,
  );
  const cycles = hostelCyclesDue(opts.checkIn, opts.today).filter(
    (cycle) =>
      !(opts.moveOut && compareYmd(cycle.billDate, opts.moveOut) > 0) &&
      (lastBilledEnd == null || compareYmd(cycle.periodStart, lastBilledEnd) > 0),
  );

  let gap: CyclePlan['gap'] = null;
  if (lastBilledEnd != null && cycles.length > 0) {
    const resumeFrom = formatYmd(addCalendarDays(parseYmd(lastBilledEnd), 1));
    if (compareYmd(cycles[0].periodStart, resumeFrom) > 0) {
      gap = {
        from: resumeFrom,
        to: formatYmd(addCalendarDays(parseYmd(cycles[0].periodStart), -1)),
      };
    }
  }
  return { cycles, gap };
}

export type MoveInEditCheck =
  | { allowed: true }
  | {
      allowed: false;
      reason: 'anniversary_changed' | 'after_billed_period' | 'misaligned';
      firstBilledStart: string;
      lastBilledEnd: string;
    };

/**
 * Whether a tenancy's move-in date may change once cycle invoices exist.
 * Allowed only when every billed period still starts on a billing
 * anniversary of the new date and billing would resume the day after the
 * last billed period, so no period is shifted, overlapped or left unbilled.
 */
export function checkMoveInEdit(opts: {
  currentCheckIn: string | null;
  newCheckIn: string;
  billed: BilledPeriod[];
}): MoveInEditCheck {
  if (opts.billed.length === 0) return { allowed: true };
  if (opts.currentCheckIn === opts.newCheckIn) return { allowed: true };

  let firstBilledStart = opts.billed[0].periodStart;
  let lastBilledEnd = opts.billed[0].periodEnd;
  for (const p of opts.billed) {
    if (compareYmd(p.periodStart, firstBilledStart) < 0) firstBilledStart = p.periodStart;
    if (compareYmd(p.periodEnd, lastBilledEnd) > 0) lastBilledEnd = p.periodEnd;
  }
  const blocked = (reason: 'anniversary_changed' | 'after_billed_period' | 'misaligned') =>
    ({ allowed: false, reason, firstBilledStart, lastBilledEnd }) as const;

  const next = parseYmd(opts.newCheckIn);
  if (opts.currentCheckIn && parseYmd(opts.currentCheckIn).day !== next.day) {
    return blocked('anniversary_changed');
  }
  if (compareYmd(opts.newCheckIn, firstBilledStart) > 0) {
    return blocked('after_billed_period');
  }

  const resumeFrom = formatYmd(addCalendarDays(parseYmd(lastBilledEnd), 1));
  const starts = new Set<string>();
  for (let n = 0; n < 1200; n += 1) {
    const start = formatYmd(addCalendarMonths(next, n));
    starts.add(start);
    if (compareYmd(start, resumeFrom) >= 0) break;
  }
  const aligned =
    starts.has(resumeFrom) && opts.billed.every((p) => starts.has(p.periodStart));
  return aligned ? { allowed: true } : blocked('misaligned');
}

/**
 * Cycle shown on Add Utilities.
 * Before the first anniversary, this is the in-progress stay (bill date still ahead).
 * On the anniversary, it is the stay that just completed.
 * After that, it is the stay whose bill date is still ahead.
 */
export function hostelCycleForInvoiceForm(
  checkInRaw: string,
  todayRaw: string,
): HostelBillingCycle {
  const checkIn = parseYmd(checkInRaw);
  const today = todayRaw.slice(0, 10);
  for (let n = 0; n < 240; n += 1) {
    const cycle = cycleAt(checkIn, n);
    if (compareYmd(cycle.billDate, today) >= 0) return cycle;
  }
  return cycleAt(checkIn, 239);
}

/** Calendar date of an instant in an IANA timezone (en-CA → YYYY-MM-DD). */
export function calendarDateInTimeZone(instant: Date, timeZone: string): string {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return fmt.format(instant);
}

/** Billing calendar zone when a property has no usable timezone configured. */
export const DEFAULT_PROPERTY_TIME_ZONE = 'Asia/Kolkata';

/**
 * Time zone policy for every property-local billing date (bill/due dates,
 * overdue, reading dates, month bounds):
 * - a valid IANA zone stored on the property is used as configured, UTC
 *   included;
 * - a missing, blank or unrecognised value falls back to
 *   DEFAULT_PROPERTY_TIME_ZONE.
 * The configured spelling is kept: ICU would canonicalise Asia/Kolkata to the
 * legacy Asia/Calcutta.
 */
export function hostelBillingTimeZone(propertyTimeZone: string | null | undefined): string {
  const tz = (propertyTimeZone ?? '').trim();
  if (!tz) return DEFAULT_PROPERTY_TIME_ZONE;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return tz;
  } catch {
    return DEFAULT_PROPERTY_TIME_ZONE;
  }
}
