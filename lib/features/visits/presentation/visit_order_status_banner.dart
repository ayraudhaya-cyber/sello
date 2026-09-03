import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/reliability/reliability_providers.dart';

/// Subtle connectivity + draft-saved indicator for visit ordering.
class VisitOrderStatusBanner extends ConsumerWidget {
  const VisitOrderStatusBanner({
    super.key,
    this.visitPendingSync = false,
    this.draftSaved = false,
  });

  final bool visitPendingSync;
  final bool draftSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(connectivitySnapshotProvider).valueOrNull;
    final online = snapshot?.transportOnline ?? true;
    final offline = !online || visitPendingSync;

    if (!offline && !draftSaved) return const SizedBox.shrink();

    final label = offline
        ? 'Offline · Changes saved on this device'
        : 'Draft saved';

    final icon = offline ? Icons.cloud_off_outlined : Icons.check_circle_outline;

    final color = offline ? AppColors.warning : AppColors.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
