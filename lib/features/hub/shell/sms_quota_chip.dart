import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/shell/sms_quota_provider.dart';

/// Where the quota block is drawn. Hidden everywhere when this company has no token.
enum SmsQuotaPlacement {
  /// Desktop Hub header, just before Quick actions.
  header,

  /// Phone and tablet menu opened from the header.
  sidebar,

  /// Settings → Notifications, under the SMS channel switch.
  settings,
}

/// Compact SMS quota. Hidden until the company has a token; retry when live
/// balance cannot be read.
class SmsQuotaChip extends ConsumerWidget {
  const SmsQuotaChip({super.key, this.placement = SmsQuotaPlacement.header});

  final SmsQuotaPlacement placement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(smsQuotaProvider);
    final view = async.asData?.value;
    if (view == null) {
      if (async.isLoading) return const SizedBox.shrink();
      return _Unavailable(
        placement: placement,
        onRetry: () {
          ref.read(smsQuotaProvider.notifier).retry();
        },
      );
    }
    if (view.isHidden) return const SizedBox.shrink();
    if (view.isUnavailable || view.quota == null) {
      return _Unavailable(
        placement: placement,
        onRetry: () => ref.read(smsQuotaProvider.notifier).retry(),
      );
    }

    final quota = view.quota!;
    final onDark = placement == SmsQuotaPlacement.sidebar;
    final fraction = quota.baseline <= 0
        ? 0.0
        : (quota.used / quota.baseline).clamp(0.0, 1.0).toDouble();
    final critical = quota.isCritical;
    final barColor = critical
        ? AppColors.attention
        : quota.isLow
        ? AppColors.warning
        : onDark
        ? AppColors.navInkStrong
        : AppColors.primary;
    final labelColor = critical
        ? AppColors.attention
        : onDark
        ? AppColors.navInk
        : AppColors.textTertiary;
    final valueColor = critical
        ? AppColors.attention
        : onDark
        ? AppColors.navInkStrong
        : AppColors.textSecondary;
    final outlineColor = critical
        ? AppColors.attention.withValues(alpha: onDark ? 0.55 : 0.45)
        : onDark
        ? const Color(0x33FFFFFF)
        : AppColors.outline;

    final bar = Tooltip(
      message: quota.tooltip,
      waitDuration: Duration.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'SMS quota',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: labelColor,
                ),
              ),
              const Spacer(),
              Text(
                quota.caption,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: valueColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                backgroundColor: critical
                    ? AppColors.attention.withValues(
                        alpha: onDark ? 0.28 : 0.16,
                      )
                    : onDark
                    ? const Color(0x33FFFFFF)
                    : AppColors.outline,
                color: barColor,
              ),
            ),
          ),
        ],
      ),
    );

    return switch (placement) {
      SmsQuotaPlacement.header => SizedBox(
        width: 188,
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: outlineColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: bar,
          ),
        ),
      ),
      SmsQuotaPlacement.sidebar => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 1, color: Color(0x1FFFFFFF)),
            const SizedBox(height: 14),
            bar,
          ],
        ),
      ),
      SmsQuotaPlacement.settings => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: bar,
      ),
    };
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.placement, required this.onRetry});

  final SmsQuotaPlacement placement;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final onDark = placement == SmsQuotaPlacement.sidebar;
    final labelColor = onDark ? AppColors.navInk : AppColors.textTertiary;
    final child = Tooltip(
      message: 'Could not load the live SMS balance. Tap to try again.',
      waitDuration: Duration.zero,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Row(
          children: [
            Icon(Icons.sms_failed_outlined, size: 16, color: labelColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'SMS quota unavailable',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: labelColor,
                ),
              ),
            ),
            Icon(Icons.refresh_rounded, size: 16, color: labelColor),
          ],
        ),
      ),
    );

    return switch (placement) {
      SmsQuotaPlacement.header => SizedBox(
        width: 188,
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: onDark ? const Color(0x33FFFFFF) : AppColors.outline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: child,
          ),
        ),
      ),
      SmsQuotaPlacement.sidebar => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 1, color: Color(0x1FFFFFFF)),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
      SmsQuotaPlacement.settings => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: child,
      ),
    };
  }
}
