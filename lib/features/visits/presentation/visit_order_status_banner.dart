import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/reliability/reliability_providers.dart';

/// Offline notice while a visit order is being saved on the device.
class VisitOrderStatusBanner extends ConsumerWidget {
  const VisitOrderStatusBanner({super.key, this.visitPendingSync = false});

  final bool visitPendingSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(connectivitySnapshotProvider).valueOrNull;
    final online = snapshot?.transportOnline ?? true;
    final offline = !online || visitPendingSync;

    if (!offline) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Offline · The visit is kept on this device. '
              'Placing orders and recording payments need a connection.',
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
