import 'package:flutter/material.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/theme/theme.dart';

/// Portrait thumbnail for records that may or may not have an image.
///
/// Uses the shared 4:5 media ratio. Falls back to a soft branded monogram
/// so lists stay visually even whether or not artwork exists.
class SelloEntityThumb extends StatelessWidget {
  const SelloEntityThumb({
    super.key,
    required this.name,
    this.imageUrl,
    this.width = 48,
    this.height,
  });

  final String name;
  final String? imageUrl;

  /// Thumbnail width. Height defaults to 4:5 portrait.
  final double width;

  /// Optional override; defaults to [width] / [MediaConstants.aspectRatio].
  final double? height;

  double get _height => height ?? (width / MediaConstants.aspectRatio);

  @override
  Widget build(BuildContext context) {
    final h = _height;
    final radius = BorderRadius.circular(width <= 48 ? 10 : 12);

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: AppColors.outlinePanel),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          imageUrl!,
          width: width,
          height: h,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _monogram(context, radius, h),
        ),
      );
    }

    return _monogram(context, radius, h);
  }

  Widget _monogram(BuildContext context, BorderRadius radius, double h) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();

    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        gradient: AppGradients.primarySoft,
        borderRadius: radius,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Center(
        child: Text(
          initial,
          style: context.texts.titleMedium?.copyWith(
            color: context.brandAccent,
            fontWeight: FontWeight.w700,
            fontSize: ((width.isFinite ? width * 0.36 : 18.0).clamp(14.0, 36.0))
                .toDouble(),
          ),
        ),
      ),
    );
  }
}
