import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Async JPEG encode for product photos on Chrome.
///
/// Canvas `toBlob` stays off the UI isolate. Logos keep the PNG path so
/// transparency survives.
Future<Uint8List?> encodeDisplayJpeg({
  required Uint8List rgba,
  required int width,
  required int height,
  required int quality,
}) async {
  if (width <= 0 || height <= 0 || rgba.isEmpty) return null;

  final canvas = HTMLCanvasElement()
    ..width = width
    ..height = height;
  final context = canvas.getContext('2d') as CanvasRenderingContext2D?;
  if (context == null) return null;

  final pixels = Uint8ClampedList.fromList(rgba);
  final imageData = ImageData(pixels.toJS, width, height.toJS);
  context.putImageData(imageData, 0, 0);

  final blob = await _toBlob(canvas, (quality.clamp(1, 100)) / 100);
  if (blob == null) return null;
  final buffer = (await blob.arrayBuffer().toDart).toDart;
  return buffer.asUint8List();
}

Future<Blob?> _toBlob(HTMLCanvasElement canvas, double quality) {
  final completer = Completer<Blob?>();
  canvas.toBlob(
    ((Blob? blob) => completer.complete(blob)).toJS,
    'image/jpeg',
    quality.toJS,
  );
  return completer.future;
}
