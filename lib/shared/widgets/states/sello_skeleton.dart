import 'package:flutter/material.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/theme/theme.dart';

/// Soft shimmer bone used to compose page skeletons.
class SelloSkeletonBone extends StatefulWidget {
  const SelloSkeletonBone({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SelloSkeletonBone> createState() => _SelloSkeletonBoneState();
}

class _SelloSkeletonBoneState extends State<SelloSkeletonBone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + 2.4 * t, 0),
              end: Alignment(-0.2 + 2.4 * t, 0),
              colors: const [
                AppColors.veil,
                Color(0xFFF7F5FC),
                AppColors.veil,
              ],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

/// Table-shaped skeleton for Hub list pages (Products, Orders, etc.).
class SelloTableSkeleton extends StatelessWidget {
  const SelloTableSkeleton({
    super.key,
    this.rows = 8,
    this.columns = 6,
    this.showMetrics = true,
  });

  final int rows;
  final int columns;
  final bool showMetrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showMetrics) ...[
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.gap),
                Expanded(
                  child: Container(
                    height: 88,
                    padding: const EdgeInsets.all(AppSpacing.mdPlus),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.panelAll,
                      border: Border.all(color: AppColors.outlinePanel),
                      boxShadow: AppShadows.panel,
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelloSkeletonBone(width: 72, height: 10),
                        Spacer(),
                        SelloSkeletonBone(width: 48, height: 22, borderRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.panelAll,
            border: Border.all(color: AppColors.outlinePanel),
            boxShadow: AppShadows.panel,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: Alignment.centerLeft,
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.outlineSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) const SizedBox(width: 28),
                      Expanded(
                        flex: i == 0 ? 2 : 1,
                        child: SelloSkeletonBone(
                          width: i == 0 ? 96 : 64,
                          height: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (var r = 0; r < rows; r++)
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    border: r == rows - 1
                        ? null
                        : const Border(
                            bottom: BorderSide(color: AppColors.outlineSubtle),
                          ),
                  ),
                  child: Row(
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: 28),
                        Expanded(
                          flex: c == 0 ? 2 : 1,
                          child: c == 0
                              ? const Row(
                                  children: [
                                    SelloSkeletonBone(
                                      width: 40,
                                      height: 40,
                                      borderRadius: 10,
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SelloSkeletonBone(
                                            width: 140,
                                            height: 12,
                                          ),
                                          SizedBox(height: 8),
                                          SelloSkeletonBone(
                                            width: 88,
                                            height: 10,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Align(
                                  alignment: c >= columns - 3
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: SelloSkeletonBone(
                                    width: c >= columns - 3 ? 56 : 72,
                                    height: 12,
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Card-list skeleton for mobile Hub lists.
class SelloListSkeleton extends StatelessWidget {
  const SelloListSkeleton({super.key, this.cards = 5});

  final int cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < cards; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.mdPlus),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.panelAll,
              border: Border.all(color: AppColors.outlinePanel),
              boxShadow: AppShadows.panel,
            ),
            child: const Row(
              children: [
                SelloSkeletonBone(width: 48, height: 48, borderRadius: 12),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelloSkeletonBone(width: 160, height: 13),
                      SizedBox(height: 10),
                      SelloSkeletonBone(width: 110, height: 10),
                    ],
                  ),
                ),
                SelloSkeletonBone(width: 52, height: 22, borderRadius: 999),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Two-column settings page skeleton.
class SelloSettingsSkeleton extends StatelessWidget {
  const SelloSettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 220,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.panelAll,
              border: Border.all(color: AppColors.outlinePanel),
              boxShadow: AppShadows.panel,
            ),
            child: Column(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        SelloSkeletonBone(
                          width: 18,
                          height: 18,
                          borderRadius: 6,
                        ),
                        SizedBox(width: 10),
                        Expanded(child: SelloSkeletonBone(height: 12)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.panelAll,
              border: Border.all(color: AppColors.outlinePanel),
              boxShadow: AppShadows.panel,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelloSkeletonBone(width: 160, height: 16),
                SizedBox(height: 10),
                SelloSkeletonBone(width: 280, height: 11),
                SizedBox(height: 28),
                SelloSkeletonBone(width: 120, height: 10),
                SizedBox(height: 10),
                SelloSkeletonBone(height: 40, borderRadius: 8),
                SizedBox(height: 20),
                SelloSkeletonBone(width: 140, height: 10),
                SizedBox(height: 10),
                SelloSkeletonBone(height: 40, borderRadius: 8),
                SizedBox(height: 20),
                SelloSkeletonBone(width: 160, height: 10),
                SizedBox(height: 10),
                SelloSkeletonBone(height: 40, borderRadius: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Soft fade-in once real content replaces a skeleton.
class SelloFadeIn extends StatelessWidget {
  const SelloFadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.normal,
      curve: AppCurves.standard,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
