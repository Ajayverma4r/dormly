// modules/tenant-portal/tenant-statement.pdf.ts
//
// Dormly-branded tenant payment statement (pdfkit). The built-in PDF fonts
// have no rupee glyph, so amounts are printed as "Rs.".

import PDFDocument from 'pdfkit';
import type { StatementResult } from './tenant-statement.service';

export type StatementPdfInput = {
  holder: { name: string; phone: string | null };
  scopeLabel: string;
  from: string | null;
  to: string | null;
  /** Property-local date the statement was generated (YYYY-MM-DD). */
  generatedOn: string;
  result: StatementResult;
};

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const BRAND = '#5218D1';
const INK = '#0F172A';
const MUTED = '#64748B';
const RULE = '#E5E7EB';

const rupees = new Intl.NumberFormat('en-IN', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export function formatAmount(v: number): string {
  return `Rs. ${rupees.format(v)}`;
}

export function formatDay(ymd: string | null): string {
  if (!ymd) return '-';
  const [y, m, d] = ymd.split('-').map(Number);
  if (!y || !m || !d) return '-';
  return `${d} ${MONTHS[m - 1]} ${y}`;
}

function formatPeriod(start: string | null, end: string | null): string {
  if (!start) return '-';
  const [y, m] = start.split('-').map(Number);
  const month = `${MONTHS[m - 1]} ${y}`;
  if (!end || end.slice(0, 7) === start.slice(0, 7)) return month;
  return `${formatDay(start)} - ${formatDay(end)}`;
}

function methodLabel(method: string | null): string {
  if (!method) return '-';
  const m = method.replace(/_/g, ' ').trim();
  return m.length <= 4 ? m.toUpperCase() : m[0].toUpperCase() + m.slice(1);
}

export const STATEMENT_COLUMNS = ['Date', 'Property', 'Invoice period', 'Method', 'Amount', 'Status'];

/** Everything printed on the statement, independent of PDF layout. */
export function statementContent(input: StatementPdfInput) {
  const { result } = input;
  const range = input.from || input.to
    ? `${input.from ? formatDay(input.from) : 'Start'} - ${input.to ? formatDay(input.to) : 'Today'}`
    : 'All dates';
  return {
    title: 'Tenant Payment Statement',
    details: [
      ['Tenant', input.holder.name],
      ...(input.holder.phone ? [['Phone', input.holder.phone]] : []),
      ['Property', input.scopeLabel],
      ['Period', range],
      ['Generated on', formatDay(input.generatedOn)],
    ] as [string, string][],
    summary: [
      ['Total payments received in period', formatAmount(result.summary.total_received)],
      ['Number of payments', String(result.summary.payment_count)],
      ['Invoices covered', String(result.summary.invoice_count)],
      [
        `Current outstanding balance (as of ${formatDay(input.generatedOn)})`,
        formatAmount(result.summary.current_outstanding),
      ],
    ] as [string, string][],
    rows: result.payments.map((p) => [
      formatDay(p.paid_on),
      p.property_name,
      formatPeriod(p.period_start, p.period_end),
      methodLabel(p.method),
      formatAmount(p.amount),
      'Received',
    ]),
    total: formatAmount(result.summary.total_received),
  };
}

export function renderStatementPdf(input: StatementPdfInput): PDFKit.PDFDocument {
  const content = statementContent(input);
  const doc = new PDFDocument({ margin: 40, size: 'A4', bufferPages: true });
  const left = 40;
  const width = doc.page.width - 80;

  doc.rect(0, 0, doc.page.width, 78).fill(BRAND);
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(22).text('Dormly', left, 22);
  doc.font('Helvetica').fontSize(11).text(content.title, left, 50);
  doc.y = 98;

  doc.fillColor(INK);
  for (const [label, value] of content.details) {
    const y = doc.y;
    doc.font('Helvetica').fontSize(9).fillColor(MUTED).text(label, left, y, { width: 110 });
    doc.font('Helvetica-Bold').fontSize(9).fillColor(INK)
      .text(value, left + 110, y, { width: width - 110 });
    doc.moveDown(0.3);
  }

  doc.moveDown(0.8);
  doc.font('Helvetica-Bold').fontSize(12).fillColor(INK).text('Summary', left);
  doc.moveDown(0.3);
  for (const [label, value] of content.summary) {
    const y = doc.y;
    doc.font('Helvetica').fontSize(9.5).fillColor(INK).text(label, left, y, { width: width - 140 });
    doc.font('Helvetica-Bold').text(value, left + width - 140, y, { width: 140, align: 'right' });
    doc.moveDown(0.3);
  }
  doc.font('Helvetica').fontSize(8).fillColor(MUTED).text(
    'The outstanding balance is the amount still owed today across the selected '
      + 'property scope. It is not limited to the period above.',
    left,
    doc.y + 2,
    { width },
  );

  doc.moveDown(1);
  doc.font('Helvetica-Bold').fontSize(12).fillColor(INK).text('Payment details', left);
  doc.moveDown(0.4);

  const widths = [70, 130, 95, 60, 85, width - 440];
  const drawHeader = () => {
    const y = doc.y;
    doc.rect(left, y - 3, width, 18).fill('#F3EEFF');
    let x = left;
    doc.font('Helvetica-Bold').fontSize(8.5).fillColor(BRAND);
    STATEMENT_COLUMNS.forEach((h, i) => {
      doc.text(h, x + 4, y + 1, { width: widths[i] - 8, align: i === 4 ? 'right' : 'left' });
      x += widths[i];
    });
    doc.y = y + 20;
  };

  if (content.rows.length === 0) {
    doc.font('Helvetica').fontSize(10).fillColor(MUTED)
      .text('No payments were recorded for this selection.', left);
  } else {
    drawHeader();
    doc.font('Helvetica').fontSize(8.5).fillColor(INK);
    for (const row of content.rows) {
      if (doc.y > doc.page.height - 90) {
        doc.addPage();
        drawHeader();
      }
      const y = doc.y;
      let x = left;
      row.forEach((cell, i) => {
        doc.font(i === 4 ? 'Helvetica-Bold' : 'Helvetica').fontSize(8.5).fillColor(INK)
          .text(cell, x + 4, y, {
            width: widths[i] - 8,
            align: i === 4 ? 'right' : 'left',
            lineBreak: false,
            ellipsis: true,
          });
        x += widths[i];
      });
      doc.moveTo(left, y + 14).lineTo(left + width, y + 14).lineWidth(0.5).stroke(RULE);
      doc.y = y + 19;
    }
    const y = doc.y + 2;
    doc.font('Helvetica-Bold').fontSize(9.5).fillColor(INK)
      .text('Total received', left + 4, y, { width: widths[0] + widths[1] + widths[2] + widths[3] - 8 });
    doc.text(content.total, left + widths[0] + widths[1] + widths[2] + widths[3] + 4, y, {
      width: widths[4] - 8,
      align: 'right',
    });
    doc.y = y + 24;
  }

  doc.font('Helvetica').fontSize(8).fillColor(MUTED)
    .text('This is a system-generated statement from Dormly.', left, doc.y + 6, { width });

  const range = doc.bufferedPageRange();
  for (let i = range.start; i < range.start + range.count; i++) {
    doc.switchToPage(i);
    const bottom = doc.page.margins.bottom;
    doc.page.margins.bottom = 0;
    doc.font('Helvetica').fontSize(8).fillColor(MUTED).text(
      `Page ${i + 1} of ${range.count}`,
      left,
      doc.page.height - 28,
      { width, align: 'right', lineBreak: false },
    );
    doc.page.margins.bottom = bottom;
  }
  doc.end();
  return doc;
}
