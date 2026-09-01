import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Domain-agnostic processed media ready for storage upload.
class ProcessedMedia extends Equatable {
  const ProcessedMedia({
    required this.bytes,
    required this.contentType,
    required this.extension,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String contentType;
  final String extension;
  final int width;
  final int height;

  int get sizeBytes => bytes.length;

  @override
  List<Object?> get props => [bytes, contentType, extension, width, height];
}

/// Upload progress phases shown in the gallery UI.
enum MediaUploadPhase {
  idle,
  preparing,
  optimizing,
  compressing,
  uploading,
  success,
  failure,
}

class MediaUploadProgress extends Equatable {
  const MediaUploadProgress({
    this.phase = MediaUploadPhase.idle,
    this.message,
    this.fraction,
  });

  final MediaUploadPhase phase;
  final String? message;
  final double? fraction;

  MediaUploadProgress copyWith({
    MediaUploadPhase? phase,
    String? message,
    double? fraction,
  }) {
    return MediaUploadProgress(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      fraction: fraction ?? this.fraction,
    );
  }

  @override
  List<Object?> get props => [phase, message, fraction];
}

/// Source channel used to acquire an image.
enum MediaSourceKind { camera, gallery, files }
