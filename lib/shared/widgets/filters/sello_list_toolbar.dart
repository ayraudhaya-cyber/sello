import 'package:flutter/material.dart';
import 'package:sello/shared/widgets/filters/sello_toolbar_body.dart';
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
    return SelloToolbarBody(
      search: SelloSearchBar(
        controller: searchController,
        hint: searchHint,
        onChanged: onSearchChanged,
      ),
      filters: filters,
      actions: actions,
    );
  }
}
