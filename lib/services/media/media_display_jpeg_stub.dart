import 'dart:typed_data';

/// Non-web hosts encode JPEG through `package:image` instead of Canvas.
Future<Uint8List?> encodeDisplayJpeg({
  required Uint8List rgba,
  required int width,
  required int height,
  required int quality,
}) async =>
    null;
