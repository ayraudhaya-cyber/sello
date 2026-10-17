import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Company block printed at the top of a report PDF.
class ReportPdfCompany {
  const ReportPdfCompany({
    required this.name,
    this.address,
    this.phone,
    this.email,
  });

  final String name;
  final String? address;
  final String? phone;
  final String? email;

  List<String> get detailLines {
    final lines = <String>[];
    final addressText = address?.trim();
    if (addressText != null && addressText.isNotEmpty) {
      lines.addAll(
        addressText
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty),
      );
    }
    final contact = <String>[
      if (phone != null && phone!.trim().isNotEmpty) phone!.trim(),
      if (email != null && email!.trim().isNotEmpty) email!.trim(),
    ];
    if (contact.isNotEmpty) lines.add(contact.join(' | '));
    return lines;
  }
}

const reportPdfMargin = pw.EdgeInsets.fromLTRB(40, 36, 40, 44);

const reportPdfInk = PdfColor.fromInt(0xFF191333);
const reportPdfMuted = PdfColor.fromInt(0xFF736C90);
const reportPdfSecondary = PdfColor.fromInt(0xFF3B3459);
const reportPdfHeaderFill = PdfColor.fromInt(0xFFF3F0FF);
const reportPdfLine = PdfColor.fromInt(0xFFEBE6F8);

pw.TextStyle reportPdfMetaStyle() =>
    const pw.TextStyle(fontSize: 8, color: reportPdfSecondary);

pw.Widget reportPdfHeader({
  required ReportPdfCompany company,
  required String title,
  required List<String> meta,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        company.name,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: reportPdfInk,
        ),
      ),
      for (final line in company.detailLines)
        pw.Text(
          line,
          style: const pw.TextStyle(fontSize: 8, color: reportPdfMuted),
        ),
      pw.SizedBox(height: 8),
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: reportPdfInk,
        ),
      ),
      for (final line in meta) pw.Text(line, style: reportPdfMetaStyle()),
      pw.SizedBox(height: 8),
      pw.Container(height: 0.6, color: reportPdfLine),
      pw.SizedBox(height: 8),
    ],
  );
}

pw.Widget reportPdfFooter(pw.Context context, String companyName) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: reportPdfLine, width: 0.4)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          companyName,
          style: const pw.TextStyle(fontSize: 8, color: reportPdfMuted),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: reportPdfMuted),
        ),
      ],
    ),
  );
}
