import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sello/features/collections/application/collections_summary.dart';
import 'package:sello/features/hub/reports/application/report_pdf_chrome.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Collected-payments PDF. Same rows and sales-rep summary as the Excel export.
abstract final class CollectionsPdfExporter {
  static Future<List<int>> buildBytes({
    required List<PaymentSummary> rows,
    required DateTime from,
    required DateTime to,
    required String repLabel,
    required String currencySymbol,
    required ReportPdfCompany company,
  }) async {
    final visible = [
      for (final row in rows)
        if (row.status == PaymentRecordStatus.completed ||
            row.status == PaymentRecordStatus.pending)
          row,
    ];
    final summary = CollectionsSummary.of(visible);
    String money(num value) =>
        SelloFormatters.currency(value, symbol: currencySymbol);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: reportPdfMargin,
        header: (context) => reportPdfHeader(
          company: company,
          title: 'Collections',
          meta: [
            'Period: ${SelloFormatters.date(from)} to ${SelloFormatters.date(to)}',
            'Sales reps: $repLabel',
          ],
        ),
        footer: (context) => reportPdfFooter(context, company.name),
        build: (context) => [
          _table(
            headers: const [
              'Date',
              'Payment no.',
              'Sales rep',
              'Customer',
              'Type',
              'Order / opening balance',
              'Amount',
              'Method',
              'Status',
              'Reference',
            ],
            rows: [
              for (final row in visible)
                [
                  _stamp(row.receivedAt),
                  row.paymentNumber,
                  row.employeeName ?? '',
                  row.customerName ?? '',
                  row.collectionTypeLabel,
                  row.allocationSummary,
                  money(row.amount),
                  row.method.label,
                  row.status == PaymentRecordStatus.pending
                      ? 'Awaiting approval'
                      : 'Collected',
                  row.reference ?? '',
                ],
            ],
            rightAligned: const {6},
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Total collected ${money(summary.collected)}. '
            'Awaiting approval ${money(summary.pending)} is listed above and is not included in collected.',
            style: const pw.TextStyle(fontSize: 8, color: reportPdfSecondary),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'By sales rep',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: reportPdfInk,
            ),
          ),
          pw.SizedBox(height: 6),
          _table(
            headers: const [
              'Sales rep',
              'Collections',
              'Collected',
              'For orders',
              'For opening balances',
              'Awaiting approval (count)',
              'Awaiting approval (amount)',
            ],
            rows: [
              for (final rep in summary.byRep)
                [
                  rep.name,
                  '${rep.collectedCount}',
                  money(rep.collected),
                  money(rep.orderCollected),
                  money(rep.openingCollected),
                  '${rep.pendingCount}',
                  money(rep.pending),
                ],
              [
                'Total',
                '${summary.collectedCount}',
                money(summary.collected),
                money(summary.orderCollected),
                money(summary.openingCollected),
                '${summary.pendingCount}',
                money(summary.pending),
              ],
            ],
            rightAligned: const {1, 2, 3, 4, 5, 6},
          ),
        ],
      ),
    );
    return doc.save();
  }

  static String _stamp(DateTime utc) {
    final d = utc.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${SelloFormatters.date(d)} $hh:$mm';
  }

  static String filename({required DateTime from, required DateTime to}) {
    String compact(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
    return 'sello-collections-${compact(from)}-${compact(to)}.pdf';
  }

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required Set<int> rightAligned,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: const pw.BoxDecoration(color: reportPdfHeaderFill),
      headerStyle: pw.TextStyle(
        fontSize: 7,
        fontWeight: pw.FontWeight.bold,
        color: reportPdfInk,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7, color: reportPdfSecondary),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        for (final index in rightAligned) index: pw.Alignment.centerRight,
      },
      headerAlignments: {
        for (final index in rightAligned) index: pw.Alignment.centerRight,
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(color: reportPdfLine, width: 0.3),
        bottom: const pw.BorderSide(color: reportPdfLine, width: 0.3),
      ),
    );
  }
}
