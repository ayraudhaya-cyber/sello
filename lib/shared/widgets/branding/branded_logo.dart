import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/constants/app_assets.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/providers/branding_provider.dart';

/// Client **wordmark** when configured, otherwise the square Sello mark.
///
/// [size] is the Sello icon edge, or the **maximum height** of a client
/// wordmark. [maxWidth] is the maximum width; if null, the parent width is
/// used. The image is contained in that box — never cropped, stretched, or
/// drawn on a plate.
class BrandedLogo extends StatelessWidget {
  const BrandedLogo({
    super.key,
    required this.size,
    this.maxWidth,
    this.branding,
    this.bytes,
    this.alignment = Alignment.centerLeft,
    this.shadows,
    this.onLightSurface = false,
  });

  final double size;
  final double? maxWidth;
  final ClientBranding? branding;
  final Uint8List? bytes;
  final Alignment alignment;
  final List<BoxShadow>? shadows;

  /// When true, uses [ClientBranding.logoLightUrl] (Sales Home). Dark chrome
  /// uses the reverse wordmark.
  final bool onLightSurface;

  @override
  Widget build(BuildContext context) {
    final url = onLightSurface ? branding?.logoLightUrl : branding?.logoUrl;
    final hasWordmark =
        (bytes != null && bytes!.isNotEmpty) || (url != null && url.isNotEmpty);

    if (!hasWordmark) {
      return _SelloMark(size: size, shadows: shadows);
    }

    final ImageProvider provider = bytes != null && bytes!.isNotEmpty
        ? MemoryImage(bytes!)
        : NetworkImage(url!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final parentWidth = constraints.maxWidth;
        final resolvedWidth = maxWidth ??
            (parentWidth.isFinite && parentWidth > 0 ? parentWidth : size * 6);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: resolvedWidth,
            maxHeight: size,
          ),
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            alignment: alignment,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            isAntiAlias: true,
            errorBuilder: (_, _, _) => _SelloMark(
              size: size < 40 ? size : 40,
            ),
          ),
        );
      },
    );
  }
}

class _SelloMark extends StatelessWidget {
  const _SelloMark({required this.size, this.shadows});

  final double size;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: shadows,
        color: AppColors.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        AppAssets.logo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Hub-rail dark surface for launch screens and branding previews.
class BrandedDarkSurface extends StatelessWidget {
  const BrandedDarkSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.expand = false,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    Widget painted = Stack(
      fit: expand ? StackFit.expand : StackFit.loose,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: context.selloColors.navRail),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: AppGradients.navRailGlow),
          ),
        ),
        Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ],
    );
    if (borderRadius != null) {
      painted = ClipRRect(borderRadius: borderRadius!, child: painted);
    }
    if (expand) {
      painted = SizedBox.expand(child: painted);
    }
    return painted;
  }
}

/// Splash / login lockup: Sello by default, or client wordmark + Powered by Sello.
class BrandedLaunchLockup extends ConsumerWidget {
  const BrandedLaunchLockup({
    super.key,
    this.showProgress = false,
    this.lightOnDark = false,
    this.clientLogoSize = 64,
  });

  final bool showProgress;
  final bool lightOnDark;

  /// Maximum height of the client wordmark.
  final double clientLogoSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider);
    final labelColor = lightOnDark
        ? AppColors.onPrimary.withValues(alpha: 0.72)
        : AppColors.textTertiary;
    final titleColor =
        lightOnDark ? AppColors.onPrimary : AppColors.textPrimary;
    final maxWordmarkWidth =
        (MediaQuery.sizeOf(context).width * 0.62).clamp(200.0, 360.0);

    if (!branding.hasCustomLogo) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandedLogo(
            size: 88,
            shadows: lightOnDark ? null : AppShadows.level2,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Sello',
            style: context.texts.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          if (showProgress) ...[
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: lightOnDark ? AppColors.onPrimary : null,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandedLogo(
          size: clientLogoSize,
          maxWidth: maxWordmarkWidth,
          branding: branding,
          alignment: Alignment.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        _PoweredBySello(color: labelColor),
        if (showProgress) ...[
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: lightOnDark ? AppColors.onPrimary : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _PoweredBySello extends StatelessWidget {
  const _PoweredBySello({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Powered by',
          style: context.texts.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 8),
        Image.asset(
          AppAssets.logo,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(width: 6),
        Text(
          'Sello',
          style: context.texts.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
