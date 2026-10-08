import 'dart:convert';

/// Single-sheet Excel-compatible workbook (SpreadsheetML), the same format as
/// the Collections export. Cells that are `num` are written as numbers;
/// everything else as text. `null` becomes an empty cell.
abstract final class ExcelTableExport {
  static List<int> buildBytes({
    required String sheetName,
    required String title,
    List<String> notes = const [],
    required List<String> headers,
    required List<List<Object?>> rows,
    List<Object?>? totals,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0"?>')
      ..writeln('<?mso-application progid="Excel.Sheet"?>')
      ..writeln(
        '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">',
      )
      ..writeln('<Styles>')
      ..writeln(
        '<Style ss:ID="header"><Font ss:Bold="1"/>'
        '<Interior ss:Color="#F3F0FF" ss:Pattern="Solid"/></Style>',
      )
      ..writeln('<Style ss:ID="bold"><Font ss:Bold="1"/></Style>')
      ..writeln('</Styles>')
      ..writeln('<Worksheet ss:Name="${_esc(_sheet(sheetName))}">')
      ..writeln('<Table>');

    _row(buffer, [_cell(title, style: 'bold')]);
    for (final note in notes) {
      _row(buffer, [_cell(note)]);
    }
    _row(buffer, const []);
    _row(buffer, [for (final h in headers) _cell(h, style: 'header')]);
    for (final row in rows) {
      _row(buffer, [for (final value in row) _cell(value)]);
    }
    if (totals != null) {
      _row(buffer, const []);
      _row(buffer, [for (final value in totals) _cell(value, style: 'bold')]);
    }

    buffer
      ..writeln('</Table>')
      ..writeln('</Worksheet>')
      ..writeln('</Workbook>');
    return [...utf8.encode('\uFEFF'), ...utf8.encode(buffer.toString())];
  }

  static String filename(String prefix, {DateTime? at}) {
    final d = (at ?? DateTime.now()).toLocal();
    final stamp =
        '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
    return 'sello-$prefix-$stamp.xls';
  }

  static String day(DateTime? value) {
    if (value == null) return '';
    final d = value.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String stamp(DateTime? value) {
    if (value == null) return '';
    final d = value.toLocal();
    return '${day(d)} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  static String _cell(Object? value, {String? style}) {
    final attr = style == null ? '' : ' ss:StyleID="$style"';
    if (value is num) {
      final text = value == value.roundToDouble()
          ? value.round().toString()
          : value.toStringAsFixed(2);
      return '<Cell$attr><Data ss:Type="Number">$text</Data></Cell>';
    }
    final text = value?.toString() ?? '';
    return '<Cell$attr><Data ss:Type="String">${_esc(text)}</Data></Cell>';
  }

  static void _row(StringBuffer buffer, List<String> cells) {
    buffer
      ..write('<Row>')
      ..writeAll(cells)
      ..writeln('</Row>');
  }

  /// Excel sheet names: max 31 chars, no `[]:*?/\`.
  static String _sheet(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
  }

  static String _esc(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
