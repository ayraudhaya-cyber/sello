import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';

/// Shown while the workspace was opened from the last saved profile.
///
/// The cache is not a fresh authorization. Sales, stock, payments, and other
/// writes still go to the server.
class CachedSessionBanner extends ConsumerWidget {
  const CachedSessionBanner({super.key});

  static const message =
      'Connection unavailable. Your access has not been rechecked.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(authSessionProvider).usingCachedProfile;
    if (!cached) return const SizedBox.shrink();

    return Material(
      color: AppColors.opsSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: AppColors.ops,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
