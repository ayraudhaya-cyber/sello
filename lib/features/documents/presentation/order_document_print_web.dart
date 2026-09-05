import 'dart:js_interop';

import 'package:sello/features/documents/presentation/order_document_print_html.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:web/web.dart' as web;

/// Opens a compact, print-ready HTML sheet (Flutter canvas print is unreliable).
void printOrderDocument(OrderDocument doc) {
  final html = buildOrderDocumentPrintHtml(doc);
  final blob = web.Blob(
    [html.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);

  final opened = web.window.open(url, '_blank');
  if (opened != null) {
    web.window.setTimeout(
      (() {
        web.URL.revokeObjectURL(url);
      }).toJS,
      60000.toJS,
    );
    return;
  }

  // Popup blocked — fall back to a hidden iframe (HTML auto-prints on load).
  final iframe = web.HTMLIFrameElement()
    ..src = url
    ..setAttribute(
      'style',
      'position:fixed;right:0;bottom:0;width:0;height:0;border:0;opacity:0;',
    );
  web.document.body?.append(iframe);

  late final web.EventListener onLoad;
  onLoad = (web.Event event) {
    iframe.removeEventListener('load', onLoad);
    web.window.setTimeout(
      (() {
        iframe.remove();
        web.URL.revokeObjectURL(url);
      }).toJS,
      2500.toJS,
    );
  }.toJS;
  iframe.addEventListener('load', onLoad);
}
