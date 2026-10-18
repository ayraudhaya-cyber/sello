import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sello/features/hub/reports/application/report_pdf_chrome.dart';
import 'package:sello/shared/models/collections_report.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Multi-page Collections Report PDF from the shared snapshot.
abstract final class CollectionsReportPdf {
  static const _totalFill = PdfColor.fromInt(0xFFFBFAFE);

  static Future<List<int>> buildBytes(
    CollectionsReportSnapshot snapshot, {
    ReportPdfCompany? company,
  }) async {
    final identity = company ?? const ReportPdfCompany(name: 'Company');
    String money(num value) =>
        SelloFormatters.currency(value, symbol: snapshot.currencySymbol);
    final asOf = SelloFormatters.date(snapshot.asOfDate);
    final period = snapshot.fromDate == null
        ? 'As of $asOf'
        : 'From ${SelloFormatters.date(snapshot.fromDate!)} to $asOf';

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: reportPdfMargin,
        header: (context) => reportPdfHeader(
          company: identity,
          title: kCollectionsReportTitle,
          meta: [
            period,
            'Sales reps: ${snapshot.salesRepsLabel}',
            if (snapshot.overdueCount > 0)
              snapshot.overdueCount == 1
                  ? '1 overdue. Follow up with the sales rep, or the owner when none is set.'
                  : '${snapshot.overdueCount} overdue. Follow up with the sales rep, or the owner when none is set.',
          ],
        ),
        footer: (context) => reportPdfFooter(context, identity.name),
        build: (context) {
          if (snapshot.isEmpty) {
            return [
              pw.SizedBox(height: 24),
              pw.Text(
                'No open invoices for this as-of date and sales-rep selection.',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: reportPdfSecondary,
                ),
              ),
            ];
          }

          return [
            for (final group in snapshot.groups) ...[
              pw.SizedBox(height: 14),
              _customerBlock(group),
              pw.SizedBox(height: 8),
              _invoiceTable(group, money),
              pw.SizedBox(height: 4),
              _subtotalRow(group, money),
            ],
            pw.SizedBox(height: 18),
            _grandTotal(snapshot, money),
          ];
        },
      ),
    );
    return doc.save();
  }

  static String filename({DateTime? asOf}) {
    final stamp = asOf ?? DateTime.now();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    return 'sello-collections-$y$m$d.pdf';
  }

  static pw.Widget _customerBlock(CollectionsReportCustomerGroup group) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          group.customerName,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: reportPdfInk,
          ),
        ),
        if (group.customerPhone != null && group.customerPhone!.isNotEmpty)
          pw.Text(
            group.customerPhone!,
            style: const pw.TextStyle(fontSize: 7.5, color: reportPdfMuted),
          ),
        pw.Text(
          group.salesRepLabel,
          style: const pw.TextStyle(fontSize: 7.5, color: reportPdfMuted),
        ),
      ],
    );
  }

  static pw.Widget _invoiceTable(
    CollectionsReportCustomerGroup group,
    String Function(num) money,
  ) {
    return pw.TableHelper.fromTextArray(
      headers: const [
        'Invoice',
        'No.',
        'Old invoice / reference',
        'Date',
        'Due',
        'Aging (days)',
        'Open Balance',
      ],
      data: [
        for (final invoice in group.invoices)
          [
            invoice.documentType,
            invoice.orderNumber,
            invoice.referenceNumber ?? '',
            SelloFormatters.date(invoice.orderedAt),
            invoice.dueLabel,
            '${invoice.agingDays}',
            money(invoice.openBalance),
          ],
      ],
      headerDecoration: const pw.BoxDecoration(color: reportPdfHeaderFill),
      headerStyle: pw.TextStyle(
        fontSize: 7,
        fontWeight: pw.FontWeight.bold,
        color: reportPdfInk,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7, color: reportPdfSecondary),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      },
      headerAlignments: {
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      },
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(color: reportPdfLine, width: 0.3),
        bottom: const pw.BorderSide(color: reportPdfLine, width: 0.3),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.1),
        1: const pw.FlexColumnWidth(1.3),
        2: const pw.FlexColumnWidth(1.4),
        3: const pw.FlexColumnWidth(1.1),
        4: const pw.FlexColumnWidth(1.8),
        5: const pw.FlexColumnWidth(0.8),
        6: const pw.FlexColumnWidth(1.1),
      },
    );
  }

  static pw.Widget _subtotalRow(
    CollectionsReportCustomerGroup group,
    String Function(num) money,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Total ${group.customerName}',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: reportPdfInk,
          ),
        ),
        pw.Text(
          money(group.subtotal),
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: reportPdfInk,
          ),
        ),
      ],
    );
  }

  static pw.Widget _grandTotal(
    CollectionsReportSnapshot snapshot,
    String Function(num) money,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _totalFill,
        border: pw.Border.all(color: reportPdfLine, width: 0.4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'GRAND TOTAL',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: reportPdfInk,
            ),
          ),
          pw.Text(
            money(snapshot.grandTotal),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: reportPdfInk,
            ),
          ),
        ],
      ),
    );
  }
}
