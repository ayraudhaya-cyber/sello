import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/utils/excel_table_export.dart';

/// Orders list as an Excel workbook — whatever filters the Owner applied.
abstract final class OrdersExcelExporter {
  static const headers = [
    'Date',
    'Order no.',
    'Customer',
    'Customer phone',
    'Sales rep',
    'Status',
    'Payment',
    'Subtotal',
    'Discount',
    'Tax',
    'Total',
    'Notes',
  ];

  static List<int> buildBytes({
    required List<OrderSummary> orders,
    String filterLabel = 'All orders',
  }) {
    final counted = [
      for (final o in orders)
        if (o.status != OrderStatus.cancelled) o,
    ];
    return ExcelTableExport.buildBytes(
      sheetName: 'Orders',
      title: 'Orders',
      notes: [
        'Filters: $filterLabel',
        'Exported: ${ExcelTableExport.stamp(DateTime.now())}',
      ],
      headers: headers,
      rows: [
        for (final o in orders)
          [
            ExcelTableExport.stamp(o.orderedAt),
            o.orderNumber,
            o.customerName ?? '',
            o.customerPhone ?? '',
            o.employeeName ?? '',
            o.status.label,
            o.paymentStatus.label,
            o.subtotal,
            o.discountAmount,
            o.taxAmount,
            o.total,
            o.notes ?? '',
          ],
      ],
      totals: [
        'Total (excluding cancelled)',
        '${counted.length} orders',
        '',
        '',
        '',
        '',
        '',
        counted.fold<num>(0, (sum, o) => sum + o.subtotal),
        counted.fold<num>(0, (sum, o) => sum + o.discountAmount),
        counted.fold<num>(0, (sum, o) => sum + o.taxAmount),
        counted.fold<num>(0, (sum, o) => sum + o.total),
      ],
    );
  }

  static String filename() => ExcelTableExport.filename('orders');
}
