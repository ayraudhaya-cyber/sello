import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/app_breakpoints.dart';
import 'package:sello/services/media/media_processor.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/media/sello_media_crop_page.dart';
import 'package:sello/shared/widgets/media/sello_media_source_sheet.dart';

/// Central Media Foundation entry point.
///
/// Source → Process → Storage. Reuse across products, avatars, logos, etc.
class MediaService {
  MediaService({
    MediaProcessor? processor,
    MediaStorageService? storage,
    ImagePicker? picker,
  })  : _processor = processor ?? const MediaProcessor(),
        _storage = storage ?? MediaStorageService(),
        _picker = picker ?? ImagePicker();

  final MediaProcessor _processor;
  final MediaStorageService _storage;
  final ImagePicker _picker;

  MediaStorageService get storage => _storage;
  MediaProcessor get processor => _processor;

  Future<XFile?> pickFromFiles() {
    return _picker.pickImage(source: ImageSource.gallery);
  }

  Future<XFile?> pickFromGallery() {
    return _picker.pickImage(source: ImageSource.gallery);
  }

  Future<List<XFile>> pickMultipleFromGallery({int? limit}) {
    return _picker.pickMultiImage(limit: limit);
  }

  Future<XFile?> captureFromCamera() {
    return _picker.pickImage(source: ImageSource.camera);
  }

  /// Mobile / narrow viewport → camera or multi gallery sheet.
  /// Desktop → open the multi-file picker immediately (no interruption).
  Future<List<XFile>> pickPhotos(
    BuildContext context, {
    required int remainingSlots,
  }) async {
    if (remainingSlots <= 0) return const [];

    if (!useMobilePicker(context)) {
      final files = await pickMultipleFromGallery(limit: remainingSlots);
      return files.take(remainingSlots).toList();
    }

    final kind = await SelloMediaSourceSheet.show(context);
    if (kind == null || !context.mounted) return const [];

    return switch (kind) {
      MediaSourceKind.camera =>
        _captureUntilLimit(context, remainingSlots),
      MediaSourceKind.gallery || MediaSourceKind.files => () async {
          final files = await pickMultipleFromGallery(limit: remainingSlots);
          return files.take(remainingSlots).toList();
        }(),
    };
  }

  Future<List<XFile>> _captureUntilLimit(
    BuildContext context,
    int remainingSlots,
  ) async {
    final files = <XFile>[];
    while (files.length < remainingSlots) {
      final file = await captureFromCamera();
      if (file == null) break;
      files.add(file);
      if (files.length >= remainingSlots || !context.mounted) break;

      final again = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add another photo?'),
          content: Text(
            'You can add ${remainingSlots - files.length} more '
            '(${files.length} of $remainingSlots for this product).',
          ),
          actions: [
            SelloButton(
              label: 'Done',
              variant: SelloButtonVariant.outline,
              size: SelloButtonSize.small,
              onPressed: () => Navigator.pop(context, false),
            ),
            SelloButton(
              label: 'Take another',
              variant: SelloButtonVariant.primary,
              size: SelloButtonSize.small,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (again != true) break;
    }
    return files;
  }

  /// Legacy single-pick path — prefer [pickPhotos] for galleries.
  Future<XFile?> pickWithBestExperience(BuildContext context) async {
    final files = await pickPhotos(context, remainingSlots: 1);
    return files.isEmpty ? null : files.first;
  }

  Future<Uint8List?> readBytes(XFile file) => file.readAsBytes();

  /// Optional portrait crop. Returns `null` when the user cancels.
  ///
  /// Opens the crop route immediately. Already-optimized gallery bytes skip the
  /// heavy prepare pass so the editor appears almost instantly.
  Future<Uint8List?> maybeCrop(
    BuildContext context,
    Uint8List bytes, {
    double aspectRatio = MediaConstants.aspectRatio,
    bool alreadyOptimized = false,
  }) async {
    if (!context.mounted) return bytes;
    return SelloMediaCropPage.open(
      context,
      aspectRatio: aspectRatio,
      loadBytes: () => _processor.prepareForCropEditor(
        bytes,
        alreadyOptimized: alreadyOptimized,
      ),
    );
  }

  Future<ProcessedMedia> compressImage(Uint8List bytes) {
    return _processor.optimize(bytes);
  }

  Future<ProcessedMedia> convertToWebP(Uint8List bytes) {
    return _processor.optimize(bytes);
  }

  /// Prepare pipeline: optional crop → optimize → WebP/JPEG.
  ///
  /// Default skips cropping so adds feel instant. Pass [offerCrop] only when
  /// the user explicitly chose "Edit Crop".
  Future<ProcessedMedia?> prepareForUpload(
    BuildContext context,
    Uint8List raw, {
    bool offerCrop = false,
    bool preferPng = false,
    void Function(MediaUploadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const MediaUploadProgress(
        phase: MediaUploadPhase.preparing,
        message: 'Preparing...',
      ),
    );

    var working = raw;
    if (offerCrop && context.mounted) {
      final cropped = await maybeCrop(context, working);
      if (cropped == null) return null;
      working = cropped;
    }

    onProgress?.call(
      const MediaUploadProgress(
        phase: MediaUploadPhase.optimizing,
        message: 'Optimizing...',
      ),
    );

    onProgress?.call(
      const MediaUploadProgress(
        phase: MediaUploadPhase.compressing,
        message: 'Compressing...',
      ),
    );

    return _processor.optimize(working, preferPng: preferPng);
  }

  /// Load bytes for an existing preview (local draft or signed URL).
  Future<Uint8List?> resolvePreviewBytes({
    Uint8List? localBytes,
    String? networkUrl,
  }) async {
    if (localBytes != null && localBytes.isNotEmpty) return localBytes;
    if (networkUrl == null || networkUrl.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(networkUrl));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<String> upload({
    required String bucket,
    required String path,
    required ProcessedMedia media,
    void Function(MediaUploadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const MediaUploadProgress(
        phase: MediaUploadPhase.uploading,
        message: 'Uploading...',
        fraction: 0.55,
      ),
    );
    final stored = await _storage.upload(
      bucket: bucket,
      path: path,
      bytes: media.bytes,
      contentType: media.contentType,
    );
    onProgress?.call(
      const MediaUploadProgress(
        phase: MediaUploadPhase.success,
        message: 'Uploaded',
        fraction: 1,
      ),
    );
    return stored;
  }

  Future<void> delete({
    required String bucket,
    required String path,
  }) {
    return _storage.delete(bucket: bucket, path: path);
  }

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
  }) {
    return _storage.createSignedUrl(bucket: bucket, path: path);
  }

  /// True when the OS likely exposes a camera (mobile / some browsers).
  static bool get cameraLikelyAvailable {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  static bool get isMobileSurface {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// Mobile UX for picking: native mobile OS, or narrow web viewport.
  static bool useMobilePicker(BuildContext context) {
    if (isMobileSurface) return true;
    return MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
  }

  /// Guard for gallery capacity.
  static void ensureCanAdd(
    int currentCount, {
    int max = MediaConstants.kMaxProductImages,
  }) {
    if (currentCount >= max) {
      throw ValidationFailure('Maximum of $max product photos.');
    }
  }
}
