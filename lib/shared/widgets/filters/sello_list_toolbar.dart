import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

class SelloListToolbar extends StatelessWidget {
  const SelloListToolbar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    this.searchHint = 'Search...',
    this.filters = const [],
    this.actions = const [],
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchHint;
  final List<Widget> filters;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final search = SizedBox(
      width: context.isMobile ? double.infinity : 320,
      child: SelloSearchBar(
        controller: searchController,
        hint: searchHint,
        onChanged: onSearchChanged,
      ),
    );

    final filterWrap = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: filters,
    );

    final actionWrap = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: actions,
    );

    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: AppSpacing.sm),
          if (filters.isNotEmpty) ...[
            filterWrap,
            const SizedBox(height: AppSpacing.sm),
          ],
          if (actions.isNotEmpty) actionWrap,
        ],
      );
    }

    return Row(
      children: [
        search,
        const SizedBox(width: AppSpacing.md),
        Expanded(child: filterWrap),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.md),
          actionWrap,
        ],
      ],
    );
  }
}
