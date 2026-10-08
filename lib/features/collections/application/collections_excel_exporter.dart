import 'dart:convert';

import 'package:sello/features/collections/application/collections_summary.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

/// Collections workbook (Excel-compatible SpreadsheetML): one sheet with every
/// collection, one summary sheet per sales rep for bonus calculation.
///
/// Collected = completed. "Awaiting approval" rows are listed but never
/// included in the Collected totals.
abstract final class CollectionsExcelExporter {
  static const _collectionHeaders = [
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
  ];

  static const _summaryHeaders = [
    'Sales rep',
    'Collections',
    'Collected',
    'For orders',
    'For opening balances',
    'Awaiting approval (count)',
    'Awaiting approval (amount)',
  ];

  static List<int> buildBytes({
    required List<PaymentSummary> rows,
    required DateTime from,
    required DateTime to,
    String repLabel = 'All sales reps',
  }) {
    final visible = [
      for (final row in rows)
        if (row.status == PaymentRecordStatus.completed ||
            row.status == PaymentRecordStatus.pending)
          row,
    ];
    final summary = CollectionsSummary.of(visible);

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
      ..writeln('</Styles>');

    // ── Sheet 1: Collections ───────────────────────────────────────────────
    buffer
      ..writeln('<Worksheet ss:Name="Collections">')
      ..writeln('<Table>');
    _row(buffer, [_s('Collections report', style: 'bold')]);
    _row(buffer, [_s('Period: ${_day(from)} to ${_day(to)}')]);
    _row(buffer, [_s('Sales reps: $repLabel')]);
    _row(buffer, []);
    _row(buffer, [for (final h in _collectionHeaders) _s(h, style: 'header')]);

    for (final row in visible) {
      _row(buffer, [
        _s(_stamp(row.receivedAt)),
        _s(row.paymentNumber),
        _s(row.employeeName ?? ''),
        _s(row.customerName ?? ''),
        _s(row.collectionTypeLabel),
        _s(row.allocationSummary),
        _n(row.amount),
        _s(row.method.label),
        _s(_statusLabel(row.status)),
        _s(row.reference ?? ''),
      ]);
    }

    _row(buffer, []);
    _row(buffer, [
      _s('Total collected', style: 'bold'),
      _s(''),
      _s(''),
      _s(''),
      _s(''),
      _s(''),
      _n(summary.collected, style: 'bold'),
    ]);
    _row(buffer, [
      _s('Awaiting approval (not included above)', style: 'bold'),
      _s(''),
      _s(''),
      _s(''),
      _s(''),
      _s(''),
      _n(summary.pending, style: 'bold'),
    ]);
    buffer
      ..writeln('</Table>')
      ..writeln('</Worksheet>');

    // ── Sheet 2: By sales rep ─────────────────────────────────────────────
    buffer
      ..writeln('<Worksheet ss:Name="By sales rep">')
      ..writeln('<Table>');
    _row(buffer, [_s('Collected by sales rep', style: 'bold')]);
    _row(buffer, [_s('Period: ${_day(from)} to ${_day(to)}')]);
    _row(buffer, []);
    _row(buffer, [for (final h in _summaryHeaders) _s(h, style: 'header')]);
    for (final rep in summary.byRep) {
      _row(buffer, [
        _s(rep.name),
        _n(rep.collectedCount),
        _n(rep.collected),
        _n(rep.orderCollected),
        _n(rep.openingCollected),
        _n(rep.pendingCount),
        _n(rep.pending),
      ]);
    }
    _row(buffer, [
      _s('Total', style: 'bold'),
      _n(summary.collectedCount, style: 'bold'),
      _n(summary.collected, style: 'bold'),
      _n(summary.orderCollected, style: 'bold'),
      _n(summary.openingCollected, style: 'bold'),
      _n(summary.pendingCount, style: 'bold'),
      _n(summary.pending, style: 'bold'),
    ]);
    buffer
      ..writeln('</Table>')
      ..writeln('</Worksheet>')
      ..writeln('</Workbook>');

    return [...utf8.encode('\uFEFF'), ...utf8.encode(buffer.toString())];
  }

  static String filename({required DateTime from, required DateTime to}) {
    String compact(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
    return 'sello-collections-${compact(from)}-${compact(to)}.xls';
  }

  static String _statusLabel(PaymentRecordStatus status) =>
      status == PaymentRecordStatus.pending ? 'Awaiting approval' : 'Collected';

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _stamp(DateTime utc) {
    final d = utc.toLocal();
    return '${_day(d)} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  static String _s(String value, {String? style}) {
    final attr = style == null ? '' : ' ss:StyleID="$style"';
    return '<Cell$attr><Data ss:Type="String">${_esc(value)}</Data></Cell>';
  }

  static String _n(num value, {String? style}) {
    final attr = style == null ? '' : ' ss:StyleID="$style"';
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(2);
    return '<Cell$attr><Data ss:Type="Number">$text</Data></Cell>';
  }

  static void _row(StringBuffer buffer, List<String> cells) {
    buffer
      ..write('<Row>')
      ..writeAll(cells)
      ..writeln('</Row>');
  }

  static String _esc(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
