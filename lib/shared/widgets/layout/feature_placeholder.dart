import 'package:flutter/material.dart';
import 'package:sello/features/hub/shared/hub_feature_page.dart';

/// Shared placeholder for undeveloped feature routes.
class FeaturePlaceholderScaffold extends StatelessWidget {
  const FeaturePlaceholderScaffold({
    super.key,
    required this.title,
    this.icon = Icons.construction_rounded,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return HubFeaturePage(title: title, icon: icon);
  }
}
