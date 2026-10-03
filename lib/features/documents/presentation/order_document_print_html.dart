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
    ..writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    )
    ..writeln(
      '<title>${_esc('${doc.kindLabel} ${doc.kindNumber}'.trim())}</title>',
    )
    ..writeln('<style>$_printCss</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<div class="sheet">');

  _writeHeader(buffer, identity, doc);
  _writeBillTo(buffer, doc, date);

  buffer.writeln('<div class="bill">');
  if (doc.purpose.isPaymentDocument) {
    _writePaymentBody(buffer, doc);
  } else {
    _writeOrderBody(buffer, doc);
  }
  buffer.writeln('</div>');

  buffer.writeln('<div class="thanks">Thank you for your business!</div>');
  if (identity.hasTerms) {
    buffer.writeln('<div class="terms">${_esc(identity.terms!)}</div>');
  }
  if (identity.hasTagline) {
    buffer.writeln('<div class="tagline">${_esc(identity.tagline!)}</div>');
  }

  buffer
    ..writeln('</div>')
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

void _writeHeader(
  StringBuffer buffer,
  DocumentIssuerIdentity identity,
  OrderDocument doc,
) {
  buffer.writeln('<header class="header">');
  buffer.writeln('<div class="brand">');
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
  buffer.writeln('</div>');
  buffer.writeln('<div class="kind">');
  buffer.writeln(
    '<div class="kind-label">${_esc(doc.kindLabel.toUpperCase())}</div>',
  );
  if (doc.kindNumber.isNotEmpty) {
    buffer.writeln('<div class="kind-number">${_esc(doc.kindNumber)}</div>');
  }
  buffer.writeln('</div>');
  buffer.writeln('</header>');

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
}

void _writeBillTo(StringBuffer buffer, OrderDocument doc, String date) {
  buffer.writeln('<section class="billto">');
  buffer.writeln('<div>');
  buffer.writeln('<div class="label">Bill To</div>');
  buffer.writeln('<div class="party">${_esc(doc.customerName)}</div>');
  if (doc.customerPhone != null) {
    buffer.writeln('<div class="party-line">${_esc(doc.customerPhone!)}</div>');
  }
  if (doc.customerAddress != null) {
    buffer.writeln(
      '<div class="party-line">${_esc(doc.customerAddress!)}</div>',
    );
  }
  if (doc.salesRepName != null) {
    buffer.writeln(
      '<div class="party-line">Sales Rep: ${_esc(doc.salesRepName!)}</div>',
    );
  }
  buffer.writeln('</div>');
  buffer.writeln('<div class="billto-right">');
  buffer.writeln('<div class="label">Date</div>');
  buffer.writeln('<div class="info-value">${_esc(date)}</div>');
  if (!doc.purpose.isPaymentDocument && doc.collectionStatusTag != null) {
    final cls = doc.collectionReview.showsPaymentDetails
        ? 'status-tag approved'
        : 'status-tag processing';
    buffer.writeln('<div class="$cls">${_esc(doc.collectionStatusTag!)}</div>');
  }
  buffer.writeln('</div>');
  buffer.writeln('</section>');
}

void _writeOrderBody(StringBuffer buffer, OrderDocument doc) {
  buffer.writeln('<table class="lines">');
  buffer.writeln(
    '<thead><tr><th class="num">#</th><th>Description</th>'
    '<th class="qty">Qty</th><th class="rate">Rate</th>'
    '<th class="amt">Amount</th></tr></thead><tbody>',
  );
  for (var i = 0; i < doc.lines.length; i++) {
    final line = doc.lines[i];
    buffer
      ..writeln('<tr>')
      ..writeln('<td class="num">${i + 1}</td>')
      ..writeln('<td>')
      ..writeln(_esc(line.displayTitle))
      ..writeln(
        line.sku?.trim().isNotEmpty == true
            ? '<div class="line-sub">${_esc(line.sku!.trim())}</div>'
            : '',
      )
      ..writeln('</td>')
      ..writeln(
        '<td class="qty">${_esc(SelloFormatters.quantity(line.quantity))}</td>',
      )
      ..writeln('<td class="rate">${_esc(doc.money(line.unitPrice))}</td>')
      ..writeln('<td class="amt">${_esc(doc.money(line.lineTotal))}</td>')
      ..writeln('</tr>');
  }
  buffer.writeln('</tbody></table>');

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

  final hasPay =
      doc.collectionReview.showsPaymentDetails ||
      doc.outstandingBalance != null;
  if (hasPay) {
    buffer.writeln('<div class="pay">');
    buffer.writeln('<div class="label">Payment details</div>');
    if (doc.collectionReview.showsPaymentDetails) {
      if (doc.collectionPaymentNumber != null) {
        _total(buffer, 'Payment', doc.collectionPaymentNumber!);
      }
      if (doc.collectionMethodLabel != null) {
        _total(buffer, 'Method', doc.collectionMethodLabel!);
      }
      if (doc.collectionPaymentAmount != null) {
        _total(
          buffer,
          'Amount received',
          doc.money(doc.collectionPaymentAmount!),
        );
      }
      if (doc.collectionReceivedAt != null) {
        _total(
          buffer,
          'Recorded on',
          SelloFormatters.date(doc.collectionReceivedAt!),
        );
      }
    }
    if (doc.outstandingBalance != null) {
      _total(buffer, 'Outstanding balance', doc.money(doc.outstandingBalance!));
    }
    buffer.writeln('</div>');
  }

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

  buffer.writeln('<div class="totals">');
  if (method != null && method.isNotEmpty) {
    _total(buffer, 'Method', method);
  }
  if (doc.reference != null) {
    _total(buffer, 'Reference', doc.reference!);
  }
  _total(
    buffer,
    'Status',
    isPending ? 'Pending Review' : (doc.paymentStatus ?? 'Recorded'),
  );
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

const _printCss = r'''
@page { size: A4; margin: 14mm 14mm; }
* { box-sizing: border-box; }
html, body {
  margin: 0;
  padding: 0;
  background: #fff;
  color: #191333;
  font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
  font-size: 11.5px;
  line-height: 1.4;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
.sheet { width: 100%; max-width: 180mm; margin: 0 auto; }
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 8px;
}
.brand { min-width: 0; }
.logo {
  display: block;
  max-width: 160px;
  max-height: 48px;
  object-fit: contain;
  margin-bottom: 6px;
}
.business {
  font-size: 15px;
  font-weight: 700;
  letter-spacing: -0.2px;
}
.kind { text-align: right; }
.kind-label {
  font-size: 18px;
  font-weight: 800;
  letter-spacing: 0.12em;
  color: #6C4FF2;
}
.kind-number {
  font-size: 15px;
  font-weight: 500;
  margin-top: 1px;
}
.contact {
  text-align: center;
  background: #EFE9FE;
  color: #3B3459;
  font-size: 10.5px;
  font-weight: 500;
  padding: 6px 10px;
  border-radius: 8px;
  margin: 8px 0 12px;
}
.contact .sep { color: #A9A2C2; padding: 0 2px; }
.billto {
  display: grid;
  grid-template-columns: 1.3fr 1fr;
  gap: 16px;
  background: #FBFAFE;
  border: 1px solid #ECE8FF;
  border-radius: 12px;
  padding: 12px 14px;
  margin-bottom: 12px;
}
.label {
  font-size: 9.5px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: #736C90;
  margin-bottom: 4px;
}
.party { font-size: 13px; font-weight: 700; }
.party-line { color: #3B3459; margin-top: 2px; }
.billto-right { text-align: right; }
.info-value { font-weight: 600; }
.status-tag {
  display: inline-block;
  margin-top: 8px;
  padding: 3px 9px;
  border-radius: 999px;
  font-size: 10.5px;
  font-weight: 600;
}
.status-tag.processing {
  background: #FAF1DF;
  color: #C9862A;
  border: 1px solid #f0dcb4;
}
.status-tag.approved {
  background: #e2f5ec;
  color: #149063;
  border: 1px solid #b7e0cc;
}
.bill {
  border: 1px solid #ECE8FF;
  border-radius: 12px;
  overflow: hidden;
  margin-bottom: 12px;
}
.lines {
  width: 100%;
  border-collapse: collapse;
}
.lines th {
  text-align: left;
  font-size: 9.5px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: #736C90;
  padding: 8px 10px;
  border-bottom: 1px solid #ECE8FF;
}
.lines td {
  padding: 7px 10px;
  border-bottom: 1px solid #F2EEFB;
  vertical-align: top;
}
.lines .num { width: 28px; color: #736C90; }
.lines .qty, .lines .rate, .lines .amt { text-align: right; white-space: nowrap; }
.lines .amt { font-weight: 600; }
.line-sub { color: #736C90; font-size: 10px; margin-top: 1px; }
.totals { padding: 10px 12px 8px; }
.total-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 3px;
  color: #3B3459;
}
.total-row.emphasize {
  margin-top: 6px;
  color: #6C4FF2;
  font-size: 16px;
  font-weight: 700;
}
.pay {
  padding: 10px 12px 12px;
  border-top: 1px solid #ECE8FF;
}
.pending {
  margin: 10px 12px;
  padding: 8px 10px;
  border-radius: 8px;
  background: #FAF1DF;
  border: 1px solid #fed7aa;
  color: #3B3459;
  font-size: 11px;
}
.notes {
  padding: 0 12px 12px;
  color: #3B3459;
  white-space: pre-wrap;
}
.thanks {
  background: #6C4FF2;
  color: #fff;
  text-align: center;
  font-weight: 600;
  font-size: 12px;
  padding: 10px 12px;
  border-radius: 10px;
}
.terms {
  margin-top: 16px;
  text-align: center;
  color: #3B3459;
  font-size: 11px;
  line-height: 1.45;
  white-space: pre-wrap;
}
.tagline {
  margin-top: 10px;
  text-align: center;
  font-size: 11.5px;
  font-weight: 500;
  color: #3B3459;
  white-space: pre-wrap;
}
@media print {
  .sheet { max-width: none; }
}
''';
