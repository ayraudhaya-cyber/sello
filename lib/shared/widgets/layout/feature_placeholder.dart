import 'package:flutter/material.dart';
import 'package:sello/shared/widgets/layout/app_page_scaffold.dart';
import 'package:sello/shared/widgets/states/sello_empty_state.dart';

/// Shared placeholder for undeveloped feature routes.
class FeaturePlaceholderScaffold extends StatelessWidget {
  const FeaturePlaceholderScaffold({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.construction_rounded,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: title,
      subtitle: description,
      body: SelloEmptyState(
        title: 'Module foundation ready',
        message:
            'Business features for this area will be implemented in a later phase.',
        icon: icon,
        tone: EmptyStateTone.brand,
      ),
    );
  }
}
