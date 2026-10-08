import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sello/shared/models/collections_report.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Multi-page Collections Report PDF from the shared snapshot.
abstract final class CollectionsReportPdf {
  static const _ink = PdfColor.fromInt(0xFF191333);
  static const _muted = PdfColor.fromInt(0xFF736C90);
  static const _secondary = PdfColor.fromInt(0xFF3B3459);
  static const _headerFill = PdfColor.fromInt(0xFFF3F0FF);
  static const _line = PdfColor.fromInt(0xFFEBE6F8);
  static const _totalFill = PdfColor.fromInt(0xFFFBFAFE);

  static Future<List<int>> buildBytes(
    CollectionsReportSnapshot snapshot,
  ) async {
    String money(num value) =>
        SelloFormatters.currency(value, symbol: snapshot.currencySymbol);
    final asOf = SelloFormatters.date(snapshot.asOfDate);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 36),
        header: (context) => _header(snapshot, asOf, context.pageNumber),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Sello Collections Report',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ),
        ),
        build: (context) {
          if (snapshot.isEmpty) {
            return [
              pw.SizedBox(height: 24),
              pw.Text(
                'No open invoices for this as-of date and sales-rep selection.',
                style: const pw.TextStyle(fontSize: 10, color: _secondary),
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

  static pw.Widget _header(
    CollectionsReportSnapshot snapshot,
    String asOf,
    int pageNumber,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          kCollectionsReportTitle,
          style: pw.TextStyle(
            fontSize: pageNumber == 1 ? 18 : 12,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'As of $asOf',
          style: const pw.TextStyle(fontSize: 10, color: _secondary),
        ),
        pw.Text(
          'Sales reps: ${snapshot.salesRepsLabel}',
          style: const pw.TextStyle(fontSize: 10, color: _secondary),
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 1, color: _line),
      ],
    );
  }

  static pw.Widget _customerBlock(CollectionsReportCustomerGroup group) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          group.customerName,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        if (group.customerPhone != null && group.customerPhone!.isNotEmpty)
          pw.Text(
            group.customerPhone!,
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
        pw.Text(
          group.salesRepLabel,
          style: const pw.TextStyle(fontSize: 9, color: _muted),
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
            '${invoice.agingDays}',
            money(invoice.openBalance),
          ],
      ],
      headerDecoration: const pw.BoxDecoration(color: _headerFill),
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8, color: _secondary),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
      headerAlignments: {
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(color: _line, width: 0.4),
        bottom: const pw.BorderSide(color: _line, width: 0.4),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.1),
        1: const pw.FlexColumnWidth(1.3),
        2: const pw.FlexColumnWidth(1.4),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.3),
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
            color: _ink,
          ),
        ),
        pw.Text(
          money(group.subtotal),
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
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
        border: pw.Border.all(color: _line, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'GRAND TOTAL',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.Text(
            money(snapshot.grandTotal),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }
}
