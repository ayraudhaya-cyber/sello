import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/media/product_image_disk_cache_stub.dart'
    if (dart.library.io) 'package:sello/shared/widgets/media/product_image_disk_cache_io.dart';

/// Product photos kept on the phone for 30 days, oldest unused files first.
///
/// The file stored is the optimized upload. List thumbnails only shrink the
/// in-memory decode, so a later fullscreen view stays sharp.
class SelloProductImageCache {
  static const _key = 'selloProductImages';

  static final CacheManager manager = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1200,
    ),
  );
}

/// Network image that uses the phone's disk cache when [cacheKey] is set.
///
/// Web keeps [Image.network] so the browser cache stays in charge.
class SelloNetworkImage extends StatelessWidget {
  const SelloNetworkImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = true,
    this.placeholder,
    this.errorBuilder,
  });

  final String url;

  /// Stable identity, usually [ProductImageCacheKey]. Null skips the disk cache.
  final String? cacheKey;
  final BoxFit? fit;
  final double? width;
  final double? height;

  /// Decode width for the in-memory image. The disk file stays full size.
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final Widget? placeholder;
  final ImageErrorWidgetBuilder? errorBuilder;

  bool get _useDiskCache =>
      !kIsWeb && productImageDiskCacheSupported && cacheKey != null;

  @override
  Widget build(BuildContext context) {
    if (!_useDiskCache) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        gaplessPlayback: gaplessPlayback,
        cacheWidth: cacheWidth,
        errorBuilder: errorBuilder,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: cacheKey,
      cacheManager: SelloProductImageCache.manager,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      filterQuality: filterQuality,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: gaplessPlayback,
      placeholder: (_, _) =>
          placeholder ?? const ColoredBox(color: AppColors.surfaceMuted),
      errorWidget: (context, _, error) =>
          errorBuilder?.call(context, error, StackTrace.empty) ??
          const ColoredBox(
            color: AppColors.surfaceMuted,
            child: Icon(
              Icons.broken_image_outlined,
              color: AppColors.textFaint,
            ),
          ),
    );
  }
}
