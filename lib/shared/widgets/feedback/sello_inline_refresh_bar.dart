import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Thin progress bar while a list/table reloads with existing rows kept visible.
class SelloInlineRefreshBar extends StatelessWidget {
  const SelloInlineRefreshBar({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: LinearProgressIndicator(
          minHeight: 3,
          backgroundColor: AppColors.primaryContainer,
          color: context.brandAccent,
        ),
      ),
    );
  }
}

/// Quiet footer spinner while the next page is appended to a list.
class SelloLoadMoreFooter extends StatelessWidget {
  const SelloLoadMoreFooter({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.brandAccent,
          ),
        ),
      ),
    );
  }
}

/// Soft notice when a reload fails but the previous rows stay on screen.
class SelloInlineErrorBar extends StatelessWidget {
  const SelloInlineErrorBar({
    super.key,
    required this.message,
    this.onRetry,
    this.lead = 'Couldn’t refresh. Showing the last loaded list.',
  });

  final String? message;
  final VoidCallback? onRetry;

  /// Plain-language first sentence before [message].
  final String lead;

  @override
  Widget build(BuildContext context) {
    final text = message?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.attentionSoft,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: AppColors.attention.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: AppColors.attention,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$lead $text',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
