import 'package:flutter/material.dart';
import 'package:sello/shared/widgets/layout/app_page_scaffold.dart';
import 'package:sello/shared/widgets/states/sello_empty_state.dart';

class HubSettingsPage extends StatelessWidget {
  const HubSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Settings',
      subtitle: 'Business settings will live here.',
      body: SelloEmptyState(
        title: 'Settings coming soon',
        message: 'Company, branch, and preference controls will plug in here.',
        icon: Icons.settings_rounded,
      ),
    );
  }
}
