import 'dart:convert';

import 'package:sello/shared/models/inventory_item.dart';

/// Builds an Excel-compatible SpreadsheetML workbook (opens natively in Excel).
abstract final class InventoryExcelExporter {
  static const _headers = [
    'Product',
    'Item code',
    'Option',
    'Option code',
    'Category',
    'Available qty',
    'On hand',
    'Reserved',
    'Status',
    'Selling price',
    'Unit',
    'Active',
  ];

  static List<int> buildBytes(List<InventoryItem> items) {
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
      ..writeln('<Worksheet ss:Name="Inventory">')
      ..writeln('<Table>');

    _writeRow(buffer, _headers, styleId: 'header');
    for (final item in items) {
      _writeRow(buffer, [
        item.name,
        item.sku,
        item.variantLabel ?? '',
        item.variantSku ?? '',
        item.categoryName ?? '',
        _num(item.availableQuantity),
        _num(item.quantity),
        _num(item.reservedQuantity),
        item.stockStatus.label,
        item.sellingPrice == null ? '' : _num(item.sellingPrice!),
        item.unitLabel ?? '',
        item.isActive ? 'Yes' : 'No',
      ]);
    }

    buffer
      ..writeln('</Table>')
      ..writeln('</Worksheet>')
      ..writeln('</Workbook>');

    // Excel prefers UTF-8 with BOM for SpreadsheetML.
    return [...utf8.encode('\uFEFF'), ...utf8.encode(buffer.toString())];
  }

  static String filename({DateTime? at}) {
    final stamp = at ?? DateTime.now();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    return 'sello-inventory-$y$m$d.xls';
  }

  static void _writeRow(
    StringBuffer buffer,
    List<String> cells, {
    String? styleId,
  }) {
    buffer.write('<Row>');
    for (final cell in cells) {
      final style = styleId == null ? '' : ' ss:StyleID="$styleId"';
      buffer.write(
        '<Cell$style><Data ss:Type="String">${_esc(cell)}</Data></Cell>',
      );
    }
    buffer.writeln('</Row>');
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
