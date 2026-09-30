import 'dart:convert';

import 'package:sello/shared/models/collections_report.dart';
import 'package:sello/shared/utils/formatters.dart';

/// SpreadsheetML export of the Collections Report — one invoice per row.
abstract final class CollectionsReportExcelExporter {
  static const headers = [
    'Customer',
    'Customer Contact',
    'Sales Rep',
    'Document Type',
    'Document No.',
    'Date',
    'Aging (days)',
    'Open Balance',
  ];

  static List<int> buildBytes(CollectionsReportSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0"?>')
      ..writeln('<?mso-application progid="Excel.Sheet"?>')
      ..writeln(
        '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">',
      )
      ..writeln('<Styles>')
      ..writeln(
        '<Style ss:ID="header"><Font ss:Bold="1"/><Interior ss:Color="#F3F0FF" ss:Pattern="Solid"/></Style>',
      )
      ..writeln('</Styles>')
      ..writeln('<Worksheet ss:Name="Collections">')
      ..writeln('<Table>');

    _writeStringRow(buffer, headers, styleId: 'header');
    for (final invoice in snapshot.invoices) {
      buffer.write('<Row>');
      _stringCell(buffer, invoice.customerName);
      _stringCell(buffer, invoice.customerPhone ?? '');
      _stringCell(buffer, invoice.salesRepName);
      _stringCell(buffer, kCollectionsDocumentType);
      _stringCell(buffer, invoice.orderNumber);
      _stringCell(buffer, SelloFormatters.date(invoice.orderedAt));
      _numberCell(buffer, invoice.agingDays);
      _numberCell(buffer, invoice.openBalance);
      buffer.writeln('</Row>');
    }

    buffer
      ..writeln('</Table>')
      ..writeln('</Worksheet>')
      ..writeln('</Workbook>');

    return [...utf8.encode('\uFEFF'), ...utf8.encode(buffer.toString())];
  }

  static String filename({DateTime? asOf}) {
    final stamp = asOf ?? DateTime.now();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    return 'sello-collections-$y$m$d.xls';
  }

  static void _writeStringRow(
    StringBuffer buffer,
    List<String> cells, {
    String? styleId,
  }) {
    buffer.write('<Row>');
    for (final cell in cells) {
      _stringCell(buffer, cell, styleId: styleId);
    }
    buffer.writeln('</Row>');
  }

  static void _stringCell(
    StringBuffer buffer,
    String value, {
    String? styleId,
  }) {
    final style = styleId == null ? '' : ' ss:StyleID="$styleId"';
    buffer.write(
      '<Cell$style><Data ss:Type="String">${_esc(value)}</Data></Cell>',
    );
  }

  static void _numberCell(StringBuffer buffer, num value) {
    buffer.write(
      '<Cell><Data ss:Type="Number">${_num(value)}</Data></Cell>',
    );
  }

  static String _num(num value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  static String _esc(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
