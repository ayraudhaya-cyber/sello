import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/feedback/sello_activity.dart';

/// Small "Saving" cue for work that continues after a dialog has closed.
///
/// It does not take taps. On a phone it sits above the bottom navigation and
/// above a full-screen dialog footer, so it does not cover those controls.
class SelloActivityPill extends StatelessWidget {
  const SelloActivityPill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const _SelloActivityPillOverlay(),
      ],
    );
  }
}

class _SelloActivityPillOverlay extends StatelessWidget {
  const _SelloActivityPillOverlay();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SelloActivity.depth,
      builder: (context, depth, _) {
        if (depth <= 0) return const SizedBox.shrink();
        final mobile = context.isMobile;
        final safe = MediaQuery.paddingOf(context);
        return Positioned(
          right: mobile ? 12 : 20,
          bottom: mobile ? safe.bottom + 84 : 20,
          child: const IgnorePointer(child: _Pill()),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) {
    final mobile = context.isMobile;
    return Semantics(
      liveRegion: true,
      label: 'Saving',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.outlinePanel),
          boxShadow: AppShadows.level2,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 10 : 12,
            vertical: mobile ? 6 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: mobile ? 14 : 16,
                height: mobile ? 14 : 16,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Saving',
                style: TextStyle(
                  fontSize: mobile ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
