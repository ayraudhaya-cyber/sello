import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/utils/excel_table_export.dart';

/// Customer list as an Excel workbook — whatever filters the Owner applied.
abstract final class CustomersExcelExporter {
  static const headers = [
    'Customer',
    'Code',
    'Company',
    'Type',
    'Mobile',
    'WhatsApp',
    'Email',
    'City',
    'Outstanding',
    'Wallet',
    'Credit allowed',
    'Credit limit',
    'Last purchase',
    'Last visit',
    'Status',
  ];

  static List<int> buildBytes({
    required List<CustomerSummary> customers,
    String filterLabel = 'All customers',
  }) {
    return ExcelTableExport.buildBytes(
      sheetName: 'Customers',
      title: 'Customers',
      notes: [
        'Filters: $filterLabel',
        'Exported: ${ExcelTableExport.stamp(DateTime.now())}',
      ],
      headers: headers,
      rows: [
        for (final c in customers)
          [
            c.name,
            c.code ?? '',
            c.companyName ?? '',
            c.customerType.label,
            c.phone ?? '',
            c.whatsapp ?? '',
            c.email ?? '',
            c.city ?? '',
            c.outstandingBalance,
            c.walletBalance,
            c.creditAllowed ? 'Yes' : 'No',
            c.creditLimit,
            ExcelTableExport.day(c.lastPurchaseAt),
            ExcelTableExport.day(c.lastVisitAt),
            c.isActive ? 'Active' : 'Inactive',
          ],
      ],
      totals: [
        'Total',
        '${customers.length} customers',
        '',
        '',
        '',
        '',
        '',
        '',
        customers.fold<num>(0, (sum, c) => sum + c.outstandingBalance),
        customers.fold<num>(0, (sum, c) => sum + c.walletBalance),
      ],
    );
  }

  static String filename() => ExcelTableExport.filename('customers');
}
