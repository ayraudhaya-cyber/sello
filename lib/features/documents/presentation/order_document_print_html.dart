import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Print-optimized HTML for customer-facing order / payment documents.
///
/// Flutter web's canvas does not print reliably (cutoff / wrong scale).
/// Opening this document in a print window fixes centering and page fit.
String buildOrderDocumentPrintHtml(OrderDocument doc) {
  final identity = doc.issuerIdentity;
  final date = SelloFormatters.date(doc.completedAt ?? doc.orderedAt);
  final buffer = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title></title>')
    ..writeln('<style>$_printCss</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<div class="sheet">');

  _writeIssuer(buffer, identity);
  buffer.writeln('<div class="card">');
  buffer.writeln('<div class="title">${_esc(doc.documentTitle)}</div>');
  buffer.writeln('<div class="date">${_esc(date)}</div>');

  if (doc.purpose.isPaymentDocument) {
    _writePaymentBody(buffer, doc);
  } else {
    _writeOrderBody(buffer, doc);
  }

  buffer.writeln('</div>'); // card

  if (identity.hasTerms) {
    buffer
      ..writeln('<div class="terms">')
      ..writeln('<div class="terms-label">Terms</div>')
      ..writeln('<div class="terms-body">${_esc(identity.terms!)}</div>')
      ..writeln('</div>');
  }

  buffer
    ..writeln('<div class="thanks">Thank you for your business!</div>')
    ..writeln('</div>') // sheet
    ..writeln('<script>')
    ..writeln(r'''
function selloPrint(){ window.focus(); window.print(); }
function selloReady(){
  var imgs = Array.prototype.slice.call(document.images || []);
  if (!imgs.length) { setTimeout(selloPrint, 80); return; }
  var left = imgs.length;
  function done(){ if (--left <= 0) setTimeout(selloPrint, 80); }
  imgs.forEach(function(img){
    if (img.complete) done();
    else { img.addEventListener("load", done); img.addEventListener("error", done); }
  });
}
window.addEventListener("load", selloReady);
window.addEventListener("afterprint", function(){ try { window.close(); } catch (e) {} });
''')
    ..writeln('</script>')
    ..writeln('</body></html>');

  return buffer.toString();
}

void _writeIssuer(StringBuffer buffer, DocumentIssuerIdentity identity) {
  buffer.writeln('<header class="issuer">');
  if (identity.showLogo && identity.logoUrl != null) {
    buffer.writeln(
      '<img class="logo" src="${_esc(identity.logoUrl!)}" alt="">',
    );
  }
  if (identity.showBusinessName) {
    buffer.writeln(
      '<div class="business">${_esc(identity.businessName)}</div>',
    );
  }
  if (identity.hasContactBlock) {
    final parts = <String>[
      if (identity.address != null) identity.address!,
      if (identity.phone != null) identity.phone!,
      if (identity.email != null) identity.email!,
    ];
    buffer.writeln(
      '<div class="contact">${parts.map(_esc).join(' <span class="sep">|</span> ')}</div>',
    );
  }
  buffer.writeln('</header>');
}

void _writeOrderBody(StringBuffer buffer, OrderDocument doc) {
  buffer.writeln('<div class="meta">');
  _meta(buffer, 'Customer', doc.customerName);
  if (doc.customerPhone != null) {
    _meta(buffer, 'Phone', doc.customerPhone!);
  }
  if (doc.customerAddress != null) {
    _meta(buffer, 'Address', doc.customerAddress!);
  }
  if (doc.salesRepName != null) {
    _meta(buffer, 'Sales Rep', doc.salesRepName!);
  }
  if (doc.outstandingBalance != null) {
    _meta(buffer, 'Outstanding balance', doc.money(doc.outstandingBalance!));
  }
  buffer.writeln('</div>');

  buffer.writeln('<div class="section-label">Items</div>');
  for (final line in doc.lines) {
    buffer
      ..writeln('<div class="line">')
      ..writeln('<div class="line-main">')
      ..writeln('<div class="line-name">${_esc(line.name)}</div>')
      ..writeln(
        '<div class="line-sub">${_esc(SelloFormatters.quantity(line.quantity))} × ${_esc(doc.money(line.unitPrice))}</div>',
      )
      ..writeln('</div>')
      ..writeln('<div class="line-total">${_esc(doc.money(line.lineTotal))}</div>')
      ..writeln('</div>');
  }

  buffer.writeln('<div class="totals">');
  _total(buffer, 'Subtotal', doc.money(doc.subtotal));
  if (doc.discountAmount > 0) {
    _total(buffer, 'Discount', '- ${doc.money(doc.discountAmount)}');
  }
  if (doc.taxAmount > 0) {
    _total(buffer, 'Tax', doc.money(doc.taxAmount));
  }
  _total(buffer, 'Total', doc.money(doc.total), emphasize: true);
  buffer.writeln('</div>');

  if (doc.notes != null) {
    buffer.writeln('<div class="notes">${_esc(doc.notes!)}</div>');
  }
}

void _writePaymentBody(StringBuffer buffer, OrderDocument doc) {
  final isPending = doc.isCollectionAcknowledgement && doc.pendingReview;
  final method = doc.paymentMethod?.replaceAll('_', ' ');

  if (isPending) {
    buffer.writeln(
      '<div class="pending">Pending Review — this collection was submitted and is waiting '
      'for owner/manager approval. Outstanding balances are not updated until it is approved.</div>',
    );
  }

  buffer.writeln('<div class="meta">');
  _meta(buffer, 'Customer', doc.customerName);
  if (doc.customerPhone != null) {
    _meta(buffer, 'Phone', doc.customerPhone!);
  }
  if (doc.salesRepName != null) {
    _meta(buffer, 'Sales Rep', doc.salesRepName!);
  }
  if (method != null && method.isNotEmpty) {
    _meta(buffer, 'Method', method);
  }
  if (doc.reference != null) {
    _meta(buffer, 'Reference', doc.reference!);
  }
  _meta(
    buffer,
    'Status',
    isPending ? 'Pending Review' : (doc.paymentStatus ?? 'Recorded'),
  );
  buffer.writeln('</div>');

  buffer.writeln('<div class="totals">');
  _total(
    buffer,
    isPending ? 'Amount submitted' : 'Amount',
    doc.money(doc.total),
    emphasize: true,
  );
  buffer.writeln('</div>');

  if (doc.notes != null) {
    buffer.writeln('<div class="notes">${_esc(doc.notes!)}</div>');
  }
}

void _meta(StringBuffer buffer, String label, String value) {
  buffer
    ..writeln('<div class="meta-row">')
    ..writeln('<span class="meta-label">${_esc(label)}</span>')
    ..writeln('<span class="meta-value">${_esc(value)}</span>')
    ..writeln('</div>');
}

void _total(
  StringBuffer buffer,
  String label,
  String value, {
  bool emphasize = false,
}) {
  final cls = emphasize ? 'total-row emphasize' : 'total-row';
  buffer
    ..writeln('<div class="$cls">')
    ..writeln('<span>${_esc(label)}</span>')
    ..writeln('<span>${_esc(value)}</span>')
    ..writeln('</div>');
}

String _esc(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

const _printCss = '''
@page { size: A4; margin: 12mm; }
* { box-sizing: border-box; }
html, body {
  margin: 0;
  padding: 0;
  background: #fff;
  color: #1c1917;
  font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
  font-size: 11.5px;
  line-height: 1.4;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
.sheet {
  width: 100%;
  max-width: 170mm;
  margin: 0 auto;
}
.issuer {
  text-align: center;
  margin: 0 0 14px;
}
.logo {
  display: block;
  margin: 0 auto 14px;
  max-width: 160px;
  max-height: 40px;
  object-fit: contain;
}
.business {
  font-size: 16px;
  font-weight: 700;
  letter-spacing: -0.2px;
  margin-bottom: 10px;
}
.contact {
  color: #57534e;
  font-size: 11px;
  line-height: 1.35;
  margin-top: 2px;
}
.contact .sep {
  color: #a8a29e;
  padding: 0 2px;
}
.card {
  border: 1px solid #e7e5e4;
  border-radius: 10px;
  padding: 14px 16px 12px;
  background: #fff;
}
.title {
  font-size: 15px;
  font-weight: 700;
}
.date {
  margin-top: 2px;
  color: #78716c;
  font-size: 11px;
}
.pending {
  margin-top: 10px;
  padding: 8px 10px;
  border-radius: 8px;
  background: #fff7ed;
  border: 1px solid #fed7aa;
  color: #57534e;
  font-size: 11px;
}
.meta {
  margin-top: 12px;
  padding-top: 10px;
  border-top: 1px solid #e7e5e4;
}
.meta-row {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  margin-bottom: 3px;
}
.meta-label {
  width: 130px;
  flex: 0 0 130px;
  color: #78716c;
}
.meta-value {
  flex: 1;
  text-align: right;
  font-weight: 600;
}
.section-label {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid #e7e5e4;
  font-weight: 600;
  margin-bottom: 8px;
}
.line {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  margin-bottom: 8px;
}
.line-main { flex: 1; min-width: 0; }
.line-name { font-weight: 600; }
.line-sub { color: #78716c; font-size: 10.5px; margin-top: 1px; }
.line-total { font-weight: 600; white-space: nowrap; }
.totals {
  margin-top: 6px;
  padding-top: 8px;
  border-top: 1px solid #e7e5e4;
}
.total-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 3px;
  color: #57534e;
}
.total-row.emphasize {
  margin-top: 6px;
  color: #1c1917;
  font-size: 13px;
  font-weight: 700;
}
.notes {
  margin-top: 10px;
  color: #57534e;
  white-space: pre-wrap;
}
.terms {
  margin-top: 12px;
}
.terms-label {
  font-weight: 600;
  color: #78716c;
  font-size: 11px;
  margin-bottom: 4px;
}
.terms-body {
  color: #57534e;
  font-size: 10.5px;
  line-height: 1.45;
  white-space: pre-wrap;
}
.thanks {
  margin-top: 14px;
  font-size: 13px;
  font-weight: 500;
  color: #57534e;
}
@media print {
  .sheet { max-width: none; }
}
''';
