import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';

/// Responsive search + filters + actions layout for white filter panels.
///
/// Uses available width (not only breakpoints) so laptop content columns with
/// a sidebar wrap instead of overflowing the card.
class SelloToolbarBody extends StatelessWidget {
  const SelloToolbarBody({
    super.key,
    required this.search,
    this.filters = const [],
    this.actions = const [],
    this.stackBelow = 1200,
  });

  final Widget search;
  final List<Widget> filters;
  final List<Widget> actions;

  /// Prefer stacked / wrapping rows when the panel is narrower than this.
  final double stackBelow;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          for (final filter in filters) ...[
            const SizedBox(height: AppSpacing.sm),
            filter,
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            if (actions.length == 1)
              actions.first
            else if (actions.length == 2)
              Row(
                children: [
                  Expanded(child: actions[0]),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: actions[1]),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    actions[i],
                  ],
                ],
              ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            context.isTablet || constraints.maxWidth < stackBelow;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              if (filters.isNotEmpty || actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    ...filters,
                    ...actions,
                  ],
                ),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: search),
            if (filters.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: filters,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        );
      },
    );
  }
}
