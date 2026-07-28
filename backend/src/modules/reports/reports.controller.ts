// modules/reports/reports.controller.ts
import { Response, NextFunction } from 'express';
import PDFDocument from 'pdfkit';
import { ReportsService } from './reports.service';
import { toCsv } from '@shared/utils/csv';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new ReportsService();

function renderTablePdf(res: Response, title: string, headers: string[], rows: (string | number)[][]) {
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${title.replace(/\s+/g, '_')}.pdf"`);

  const doc = new PDFDocument({ margin: 40, size: 'A4' });
  doc.pipe(res);

  doc.fontSize(18).text(title, { align: 'left' });
  doc.moveDown();

  const colWidth = (doc.page.width - 80) / headers.length;
  const startX = 40;
  let y = doc.y;

  doc.fontSize(9).font('Helvetica-Bold');
  headers.forEach((h, i) => doc.text(h, startX + i * colWidth, y, { width: colWidth }));
  y += 18;
  doc.moveTo(startX, y).lineTo(doc.page.width - 40, y).stroke();
  y += 6;

  doc.font('Helvetica').fontSize(8);
  for (const row of rows) {
    if (y > doc.page.height - 60) {
      doc.addPage();
      y = 40;
    }
    row.forEach((cell, i) => doc.text(String(cell), startX + i * colWidth, y, { width: colWidth }));
    y += 16;
  }

  doc.end();
}

export class ReportsController {
  rentCollection = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const { startDate, endDate, format } = req.query as { startDate: string; endDate: string; format: string };
      const rows = await service.getRentCollectionRows(req.params.propertyId, startDate, endDate);

      const headers = ['Tenant', 'Phone', 'Unit', 'Period Start', 'Period End', 'Due Date', 'Status', 'Total', 'Paid', 'Pending'];
      const dataRows = rows.map((r) => [
        r.full_name, r.phone, r.node_name,
        r.period_start?.toISOString().split('T')[0], r.period_end?.toISOString().split('T')[0],
        r.due_date?.toISOString().split('T')[0], r.status,
        Number(r.total_amount).toFixed(0), Number(r.paid_amount).toFixed(0),
        (Number(r.total_amount) - Number(r.paid_amount)).toFixed(0),
      ]);

      if (format === 'csv') {
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', 'attachment; filename="rent_collection.csv"');
        return res.send(toCsv(headers, dataRows));
      }
      renderTablePdf(res, 'Rent Collection Report', headers, dataRows);
    } catch (err) { next(err); }
  };

  occupancy = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const { format } = req.query as { format: string };
      const rows = await service.getOccupancyRows(req.params.propertyId);

      const headers = ['Level', 'Unit', 'Status', 'Tenant', 'Phone', 'Move-in Date'];
      const dataRows = rows.map((r) => [
        r.level_name, r.node_name, r.occupancy_status,
        r.full_name ?? '-', r.phone ?? '-',
        r.move_in_at ? r.move_in_at.toISOString().split('T')[0] : '-',
      ]);

      if (format === 'csv') {
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', 'attachment; filename="occupancy.csv"');
        return res.send(toCsv(headers, dataRows));
      }
      renderTablePdf(res, 'Occupancy Report', headers, dataRows);
    } catch (err) { next(err); }
  };
}