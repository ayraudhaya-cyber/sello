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
