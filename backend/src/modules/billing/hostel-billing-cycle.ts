// Monthly billing cycle for every property type.
// bill date = check-in anniversary + N calendar months (not +30 days)
// default due date = bill date + 4 calendar days
// Owner-edited due dates live on invoices.due_date and are never rewritten here.

export type Ymd = { year: number; month: number; day: number };

export type HostelBillingCycle = {
  /** YYYY-MM-DD — check-in anniversary when the bill is created. */
  billDate: string;
  /** YYYY-MM-DD — bill date + 4 calendar days. Owner may replace this on the invoice. */
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
 * due date = bill date + 4 calendar days
 */
function cycleAt(checkIn: Ymd, index: number): HostelBillingCycle {
  const periodStartDate = addCalendarMonths(checkIn, index);
  const bill = addCalendarMonths(checkIn, index + 1);
  const billDate = formatYmd(bill);
  return {
    billDate,
    dueDate: formatYmd(addCalendarDays(bill, 4)),
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

/**
 * Check-in pickers send local midnight as UTC. Property timezone defaults to
 * UTC, which would shift the calendar day. Hostel billing uses the property
 * zone, and Asia/Kolkata when the zone is missing or still the UTC default.
 */
export function hostelBillingTimeZone(propertyTimeZone: string | null | undefined): string {
  const tz = (propertyTimeZone ?? '').trim();
  if (!tz || tz.toUpperCase() === 'UTC') return 'Asia/Kolkata';
  return tz;
}
