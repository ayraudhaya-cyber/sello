import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Settings → Account — personal sign-in security only (no email/profile edits).
class AccountSettingsSection extends ConsumerWidget {
  const AccountSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroupCard(
          title: 'Sign-in',
          description:
              'Change the password for your own account. Email, name, and '
              'role changes are managed by an Owner or Manager in Team.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (session != null) ...[
                _AccountReadOnlyRow(
                  label: 'Signed in as',
                  value: session.email.isEmpty ? '—' : session.email,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: SelloButton(
                  label: 'Change password',
                  icon: Icons.lock_outline_rounded,
                  variant: SelloButtonVariant.secondary,
                  onPressed: () => showChangePasswordDialog(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountReadOnlyRow extends StatelessWidget {
  const _AccountReadOnlyRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.texts.bodySmall?.copyWith(
              color: context.selloColors.textSecondary,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
