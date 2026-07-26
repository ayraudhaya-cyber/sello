import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/theme/theme.dart';

/// Horizontal breadcrumb trail for Hub / desktop chrome.
class SelloBreadcrumbs extends StatelessWidget {
  const SelloBreadcrumbs({
    super.key,
    required this.items,
  });

  final List<BreadcrumbData> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: context.selloColors.textTertiary,
              ),
            ),
          _Crumb(
            data: items[i],
            isLast: i == items.length - 1,
          ),
        ],
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.data, required this.isLast});

  final BreadcrumbData data;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final style = context.texts.labelMedium?.copyWith(
      color: isLast
          ? AppColors.textPrimary
          : context.selloColors.textSecondary,
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
    );

    if (isLast || data.path == null) {
      return Text(data.label, style: style);
    }

    return InkWell(
      onTap: () => context.go(data.path!),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: 2,
        ),
        child: Text(data.label, style: style),
      ),
    );
  }
}
