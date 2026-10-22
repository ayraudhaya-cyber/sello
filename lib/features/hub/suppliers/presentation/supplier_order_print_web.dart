import 'dart:js_interop';

import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/shared/models/supplier_order.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:web/web.dart' as web;

void printSupplierOrder(
  SupplierOrderSummary order,
  String currencySymbol,
  DocumentIssuerIdentity identity,
) {
  final rows = order.lines
      .map(
        (line) =>
            '<tr><td>${_esc(line.title)}</td>'
            '<td>${_esc(SelloFormatters.quantity(line.quantity))}</td>'
            '<td>${_esc(SelloFormatters.currency(line.unitCost, symbol: currencySymbol))}</td>'
            '<td>${_esc(SelloFormatters.currency(line.lineTotal, symbol: currencySymbol))}</td></tr>',
      )
      .join();
  final logo = identity.showLogo && identity.logoUrl != null
      ? '<img class="logo" src="${_esc(identity.logoUrl!)}" alt="">'
      : '';
  final name = identity.showBusinessName
      ? '<div class="business">${_esc(identity.businessName)}</div>'
      : '';
  final contact = <String>[
    if (identity.address != null) identity.address!,
    if (identity.phone != null) identity.phone!,
    if (identity.email != null) identity.email!,
  ];
  final contactHtml = contact.isEmpty
      ? ''
      : '<p class="contact">${contact.map(_esc).join(' · ')}</p>';
  final date = order.orderedAt ?? order.createdAt;
  final html = '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>${_esc(order.orderNumber)}</title>
<style>
  body { font-family: Georgia, serif; color: #1c1b22; margin: 32px; }
  .logo { max-width: 180px; max-height: 64px; object-fit: contain; margin-bottom: 8px; }
  .business { font-size: 18px; font-weight: 700; margin-bottom: 4px; }
  .contact { margin: 0 0 18px; color: #5c5966; font-size: 13px; }
  h1 { font-size: 13px; letter-spacing: 0.08em; margin: 18px 0 4px; color: #5c5966; }
  .number { font-size: 20px; font-weight: 700; margin: 0 0 16px; }
  .meta { margin: 0 0 18px; }
  .label { font-size: 11px; letter-spacing: 0.06em; color: #5c5966; text-transform: uppercase; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 8px 0; border-bottom: 1px solid #e6e2ea; }
  th:nth-child(n+2), td:nth-child(n+2) { text-align: right; }
  .total { margin-top: 16px; font-weight: 700; }
</style>
</head>
<body onload="window.print()">
  $logo
  $name
  $contactHtml
  <h1>PURCHASE ORDER</h1>
  <div class="number">${_esc(order.orderNumber)}</div>
  <p class="meta"><span class="label">To</span><br>${_esc(order.supplierName)}</p>
  <p class="meta"><span class="label">Date</span><br>${_esc(SelloFormatters.date(date))}</p>
  <table>
    <thead><tr><th>Product</th><th>Qty</th><th>Cost</th><th>Amount</th></tr></thead>
    <tbody>$rows</tbody>
  </table>
  <p class="total">Total ${_esc(SelloFormatters.currency(order.total, symbol: currencySymbol))}</p>
</body>
</html>
''';
  final blob = web.Blob(
    [html.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
}

String _esc(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
