import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:sello/shared/utils/product_image_cache_key.dart';

/// Persisted product gallery row (+ optional signed URL / local draft bytes).
class ProductImage extends Equatable {
  const ProductImage({
    required this.id,
    required this.productId,
    required this.storagePath,
    required this.sortOrder,
    required this.isPrimary,
    this.updatedAt,
    this.networkUrl,
    this.localBytes,
    this.pendingUpload = false,
  });

  final String id;
  final String productId;
  final String storagePath;
  final int sortOrder;
  final bool isPrimary;

  /// When this photo file was last replaced. Part of the disk-cache key.
  final DateTime? updatedAt;
  final String? networkUrl;

  String? get cacheKey => ProductImageCacheKey.of(storagePath, updatedAt);
  final Uint8List? localBytes;
  final bool pendingUpload;

  bool get hasPreview =>
      localBytes != null || (networkUrl != null && networkUrl!.isNotEmpty);

  ProductImage copyWith({
    String? id,
    String? productId,
    String? storagePath,
    int? sortOrder,
    bool? isPrimary,
    DateTime? updatedAt,
    String? networkUrl,
    Uint8List? localBytes,
    bool? pendingUpload,
    bool clearLocalBytes = false,
    bool clearNetworkUrl = false,
  }) {
    return ProductImage(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      storagePath: storagePath ?? this.storagePath,
      sortOrder: sortOrder ?? this.sortOrder,
      isPrimary: isPrimary ?? this.isPrimary,
      updatedAt: updatedAt ?? this.updatedAt,
      networkUrl: clearNetworkUrl ? null : (networkUrl ?? this.networkUrl),
      localBytes: clearLocalBytes ? null : (localBytes ?? this.localBytes),
      pendingUpload: pendingUpload ?? this.pendingUpload,
    );
  }

  factory ProductImage.fromJson(Map<String, dynamic> json) {
    return ProductImage(
      id: json['id'] as String,
      productId: json['product_id'] as String? ?? '',
      storagePath: json['storage_path'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isPrimary: json['is_primary'] as bool? ?? false,
      updatedAt: _dateValue(json['updated_at']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    productId,
    storagePath,
    sortOrder,
    isPrimary,
    updatedAt,
    networkUrl,
    localBytes,
    pendingUpload,
  ];
}

/// Local editor draft slot before / during save.
class MediaGalleryDraft extends Equatable {
  const MediaGalleryDraft({
    required this.clientId,
    this.remoteId,
    this.storagePath,
    this.networkUrl,
    this.localBytes,
    this.isPrimary = false,
    this.sortOrder = 0,
    this.dirty = false,
    this.removed = false,
    this.processing = false,
    this.optimized = false,
    this.imageUpdatedAt,
  });

  final String clientId;
  final String? remoteId;
  final String? storagePath;
  final String? networkUrl;
  final Uint8List? localBytes;
  final bool isPrimary;
  final int sortOrder;
  final bool dirty;
  final bool removed;

  /// True while background optimization is running for this slot.
  final bool processing;

  /// True after local bytes have been resized/compressed for upload.
  final bool optimized;

  /// When the stored photo was last replaced. Null for a photo not yet saved.
  final DateTime? imageUpdatedAt;

  String? get cacheKey => ProductImageCacheKey.of(storagePath, imageUpdatedAt);

  bool get hasPreview =>
      localBytes != null || (networkUrl != null && networkUrl!.isNotEmpty);

  bool get isNew => remoteId == null;

  MediaGalleryDraft copyWith({
    String? clientId,
    String? remoteId,
    String? storagePath,
    String? networkUrl,
    Uint8List? localBytes,
    bool? isPrimary,
    int? sortOrder,
    bool? dirty,
    bool? removed,
    bool? processing,
    bool? optimized,
    DateTime? imageUpdatedAt,
    bool clearLocalBytes = false,
    bool clearNetworkUrl = false,
    bool clearRemote = false,
  }) {
    return MediaGalleryDraft(
      clientId: clientId ?? this.clientId,
      remoteId: clearRemote ? null : (remoteId ?? this.remoteId),
      storagePath: storagePath ?? this.storagePath,
      networkUrl: clearNetworkUrl ? null : (networkUrl ?? this.networkUrl),
      localBytes: clearLocalBytes ? null : (localBytes ?? this.localBytes),
      isPrimary: isPrimary ?? this.isPrimary,
      sortOrder: sortOrder ?? this.sortOrder,
      dirty: dirty ?? this.dirty,
      removed: removed ?? this.removed,
      processing: processing ?? this.processing,
      optimized: optimized ?? this.optimized,
      imageUpdatedAt: imageUpdatedAt ?? this.imageUpdatedAt,
    );
  }

  static MediaGalleryDraft fromProductImage(ProductImage image) {
    return MediaGalleryDraft(
      clientId: image.id,
      remoteId: image.id,
      storagePath: image.storagePath,
      networkUrl: image.networkUrl,
      localBytes: image.localBytes,
      isPrimary: image.isPrimary,
      sortOrder: image.sortOrder,
      optimized: true,
      imageUpdatedAt: image.updatedAt,
    );
  }

  static MediaGalleryDraft local({
    required String clientId,
    required Uint8List bytes,
    required int sortOrder,
    required bool isPrimary,
    bool processing = false,
    bool optimized = false,
  }) {
    return MediaGalleryDraft(
      clientId: clientId,
      localBytes: bytes,
      sortOrder: sortOrder,
      isPrimary: isPrimary,
      dirty: true,
      processing: processing,
      optimized: optimized,
    );
  }

  @override
  List<Object?> get props => [
    clientId,
    remoteId,
    storagePath,
    networkUrl,
    localBytes,
    isPrimary,
    sortOrder,
    dirty,
    removed,
    processing,
    optimized,
    imageUpdatedAt,
  ];
}

DateTime? _dateValue(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}
