import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/filters/sello_clear_filters_bar.dart';

/// Responsive search + filters + actions layout for white filter panels.
///
/// Uses available width (not only breakpoints) so laptop content columns with
/// a sidebar wrap instead of overflowing the card.
///
/// When there are three or more filters (or [filtersOnOwnRow] is true), search
/// and actions stay on the first row and filters sit on a full-width row below
/// — avoids a lone wrapped dropdown hanging under the search field.
class SelloToolbarBody extends StatelessWidget {
  const SelloToolbarBody({
    super.key,
    required this.search,
    this.filters = const [],
    this.actions = const [],
    this.stackBelow = 1200,
    this.filtersOnOwnRow,
    this.onClearFilters,
  });

  final Widget search;
  final List<Widget> filters;
  final List<Widget> actions;

  /// Prefer stacked / wrapping rows when the panel is narrower than this.
  final double stackBelow;

  /// Force filters onto a second row. Defaults to true when [filters].length ≥ 3.
  final bool? filtersOnOwnRow;

  /// Shown as a text link at the end of the filter row.
  final VoidCallback? onClearFilters;

  bool get _filtersOnOwnRow => filtersOnOwnRow ?? filters.length >= 3;

  List<Widget> get _filters {
    final clear = onClearFilters;
    if (clear == null) return filters;
    return [...filters, SelloClearFiltersLink(onPressed: clear)];
  }

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          for (final filter in _filters) ...[
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
        final narrow = context.isTablet || constraints.maxWidth < stackBelow;

        if (narrow || _filtersOnOwnRow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: search),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.sm),
                    ..._spaced(actions, AppSpacing.xs),
                  ],
                ],
              ),
              if (_filters.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _filters,
                ),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: search),
            if (_filters.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _filters,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              ..._spaced(actions, AppSpacing.xs),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _spaced(List<Widget> children, double gap) {
    if (children.isEmpty) return const [];
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        children[i],
      ],
    ];
  }
}
