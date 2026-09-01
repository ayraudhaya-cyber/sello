import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/shared/models/processed_media.dart';

/// Image processing pipeline — resize, compress, strip metadata.
///
/// On web, encoding stays on an async Skia path (PNG) so the UI isolate is
/// never blocked by synchronous Dart JPEG work — users can keep typing.
/// On IO platforms, JPEG encode runs in a background isolate via [compute].
class MediaProcessor {
  const MediaProcessor();

  /// Longest edge for the crop editor — keeps open/apply snappy on large photos.
  /// Web stays closer to the gallery optimize size so PNG encode isn't huge.
  static int get cropEditorMaxDimension => kIsWeb ? 1200 : 1600;

  /// Payloads at or under this size are already fine for the crop UI — skip
  /// the expensive decode → PNG re-encode pass (the main "Preparing photo…" cost).
  static const int _cropSkipPrepareBytes = 1024 * 1024;

  /// Slightly smaller on web so async encode finishes faster.
  static int get _optimizeMaxDimension =>
      kIsWeb ? 1000 : MediaConstants.maxDimension;

  /// Shrink by the longer edge only. Passing both codec targets squashes
  /// the image to a square (wordmarks become thin and tall).
  @visibleForTesting
  static ({int? width, int? height}) codecTargets({
    required int sourceWidth,
    required int sourceHeight,
    required int maxEdge,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return (width: null, height: null);
    }
    final longest =
        sourceWidth >= sourceHeight ? sourceWidth : sourceHeight;
    if (longest <= maxEdge) {
      return (width: null, height: null);
    }
    if (sourceWidth >= sourceHeight) {
      return (width: maxEdge, height: null);
    }
    return (width: null, height: maxEdge);
  }

  Future<ProcessedMedia> optimize(
    Uint8List source, {
    int? maxDimension,
    int quality = MediaConstants.jpegQuality,
    bool preferPng = false,
  }) async {
    if (source.isEmpty) {
      throw const ValidationFailure('The selected image is empty.');
    }
    if (source.lengthInBytes > MediaConstants.maxSourceBytes) {
      throw const ValidationFailure(
        'Image is larger than 5MB. Choose a smaller photo.',
      );
    }

    final dim = maxDimension ?? _optimizeMaxDimension;
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(source);
      image = (await codec.getNextFrame()).image;
      final targets = codecTargets(
        sourceWidth: image.width,
        sourceHeight: image.height,
        maxEdge: dim,
      );
      if (targets.width != null || targets.height != null) {
        image.dispose();
        image = null;
        codec.dispose();
        codec = await ui.instantiateImageCodec(
          source,
          targetWidth: targets.width,
          targetHeight: targets.height,
        );
        image = (await codec.getNextFrame()).image;
      }

      // Let input events run before heavy pixel work.
      await Future<void>.delayed(Duration.zero);

      if (kIsWeb || preferPng) {
        // Fully async — does not freeze text fields on Chrome.
        // Logos stay PNG so reverse wordmarks keep transparency.
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) {
          throw const ValidationFailure(
            'Unable to optimize that image.',
          );
        }
        return ProcessedMedia(
          bytes: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          contentType: 'image/png',
          extension: 'png',
          width: image.width,
          height: image.height,
        );
      }

      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw const ValidationFailure(
          'Unable to read that image. Try PNG, JPG, or WEBP.',
        );
      }

      await Future<void>.delayed(Duration.zero);

      return compute(
        _encodeJpegIsolate,
        _EncodeRequest(
          rgba: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
          width: image.width,
          height: image.height,
          quality: quality,
          targetMaxBytes: MediaConstants.targetMaxBytes,
        ),
      );
    } on ValidationFailure {
      rethrow;
    } catch (_) {
      throw const ValidationFailure(
        'Unable to read that image. Try PNG, JPG, or WEBP.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// Downscale for the crop UI so Crop widget doesn't decode multi‑MB originals.
  ///
  /// Already-optimized gallery bytes are returned as-is — re-encoding to PNG on
  /// web is what made "Preparing photo…" feel stuck for several seconds.
  Future<Uint8List> prepareForCropEditor(
    Uint8List source, {
    bool alreadyOptimized = false,
  }) async {
    if (source.isEmpty) {
      throw const ValidationFailure('The selected image is empty.');
    }

    // Fast path: gallery-optimized or already compact payloads.
    if (alreadyOptimized || source.lengthInBytes <= _cropSkipPrepareBytes) {
      return source;
    }

    ui.Codec? codec;
    ui.Image? image;
    try {
      final maxDim = cropEditorMaxDimension;
      codec = await ui.instantiateImageCodec(source);
      image = (await codec.getNextFrame()).image;
      final targets = codecTargets(
        sourceWidth: image.width,
        sourceHeight: image.height,
        maxEdge: maxDim,
      );
      if (targets.width != null || targets.height != null) {
        image.dispose();
        image = null;
        codec.dispose();
        codec = await ui.instantiateImageCodec(
          source,
          targetWidth: targets.width,
          targetHeight: targets.height,
        );
        image = (await codec.getNextFrame()).image;
      }

      // If Skia didn't need to shrink much, keep the original encoded bytes.
      final longest = image.width > image.height ? image.width : image.height;
      if (longest <= maxDim && source.lengthInBytes <= 2 * 1024 * 1024) {
        return source;
      }

      await Future<void>.delayed(Duration.zero);

      // Prefer raw→JPEG on IO; on web stay with async PNG but at a smaller size.
      if (!kIsWeb) {
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rgba == null) {
          throw const ValidationFailure(
            'Unable to prepare that image for cropping.',
          );
        }
        final encoded = await compute(
          _encodeJpegIsolate,
          _EncodeRequest(
            rgba: rgba.buffer
                .asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
            width: image.width,
            height: image.height,
            quality: 88,
            targetMaxBytes: 900 * 1024,
          ),
        );
        return encoded.bytes;
      }

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw const ValidationFailure(
          'Unable to prepare that image for cropping.',
        );
      }
      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } on ValidationFailure {
      rethrow;
    } catch (_) {
      throw const ValidationFailure(
        'Unable to prepare that image for cropping.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

class _EncodeRequest {
  const _EncodeRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.quality,
    required this.targetMaxBytes,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
  final int targetMaxBytes;
}

ProcessedMedia _encodeJpegIsolate(_EncodeRequest request) {
  final image = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: request.rgba.buffer,
    bytesOffset: request.rgba.offsetInBytes,
    rowStride: request.width * 4,
    order: img.ChannelOrder.rgba,
  );

  var jpegQuality = request.quality;
  var jpegBytes = Uint8List.fromList(
    img.encodeJpg(image, quality: jpegQuality),
  );
  if (jpegBytes.lengthInBytes > request.targetMaxBytes && jpegQuality > 70) {
    jpegQuality = 72;
    jpegBytes = Uint8List.fromList(
      img.encodeJpg(image, quality: jpegQuality),
    );
  }

  return ProcessedMedia(
    bytes: jpegBytes,
    contentType: MediaConstants.jpegContentType,
    extension: MediaConstants.jpegExtension,
    width: request.width,
    height: request.height,
  );
}
