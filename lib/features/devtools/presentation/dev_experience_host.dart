import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/devtools/application/dev_experience_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Side-effect only: auto-login. Does not wrap UI in a Stack/Overlay.
class DevExperienceBootstrap extends ConsumerStatefulWidget {
  const DevExperienceBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DevExperienceBootstrap> createState() =>
      _DevExperienceBootstrapState();
}

class _DevExperienceBootstrapState
    extends ConsumerState<DevExperienceBootstrap> {
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return widget.child;

    ref.listen<AuthSessionState>(authSessionProvider, (_, next) {
      ref.read(devExperienceProvider.notifier).maybeAutoLogin(next);
    });

    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(devExperienceProvider.notifier).maybeAutoLogin(
              ref.read(authSessionProvider),
            );
      });
    }

    return widget.child;
  }
}

/// Opens the DX tools panel as a standard dialog (uses navigator Overlay).
Future<void> showDevExperienceDialog(BuildContext context) {
  if (kReleaseMode) return Future<void>.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => const _DevExperienceDialog(),
  );
}

/// Compact top-bar control — only built in non-release modes.
class DevExperienceToolbarButton extends StatelessWidget {
  const DevExperienceToolbarButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: const Color(0xFFFF6D00),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () => showDevExperienceDialog(context),
          borderRadius: BorderRadius.circular(999),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.developer_mode_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'DX',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevExperienceDialog extends ConsumerWidget {
  const _DevExperienceDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dev = ref.watch(devExperienceProvider);
    final auth = ref.watch(authSessionProvider);
    final session = auth.session;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialogAll),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                children: [
                  const SelloIconBadge(
                    icon: Icons.developer_mode_rounded,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Development', style: context.texts.titleLarge),
                        Text(
                          'Debug tools using the real auth flow.',
                          style: context.texts.bodySmall?.copyWith(
                            color: context.selloColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto Login'),
                      subtitle: Text(
                        dev.selectedAccount == null
                            ? 'Configure a development user in `.env`.'
                            : 'Default user: ${dev.selectedAccount!.label}',
                      ),
                      value: dev.autoLoginEnabled,
                      onChanged: dev.hasAccounts
                          ? ref
                              .read(devExperienceProvider.notifier)
                              .setAutoLoginEnabled
                          : null,
                    ),
                    const Divider(height: AppSpacing.xl),
                    Text(
                      'Development Accounts',
                      style: context.texts.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (!dev.hasAccounts)
                      const Text(
                        'No DX accounts configured. Add DX_* credentials to `.env` and run with --dart-define-from-file=.env.',
                      )
                    else
                      for (final account in dev.accounts)
                        Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: AppRadius.cardAll,
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => ref
                                    .read(devExperienceProvider.notifier)
                                    .selectAccount(account.id),
                                customBorder: const CircleBorder(),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    dev.selectedAccountId == account.id
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: dev.selectedAccountId == account.id
                                        ? context.brandAccent
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      account.label,
                                      style: context.texts.labelLarge,
                                    ),
                                    Text(
                                      account.email,
                                      style: context.texts.bodySmall?.copyWith(
                                        color:
                                            context.selloColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SelloButton(
                                label: 'Login',
                                size: SelloButtonSize.small,
                                variant: SelloButtonVariant.outline,
                                loading: dev.isBusy,
                                onPressed: () async {
                                  await ref
                                      .read(devExperienceProvider.notifier)
                                      .signInAs(account.id);
                                  if (context.mounted) {
                                    Navigator.of(context).maybePop();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    const Divider(height: AppSpacing.xl),
                    Text('Session Tools', style: context.texts.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        SelloButton(
                          label: 'Reload Session',
                          icon: Icons.refresh_rounded,
                          variant: SelloButtonVariant.outline,
                          loading: dev.isBusy,
                          onPressed: () => ref
                              .read(devExperienceProvider.notifier)
                              .reloadSession(),
                        ),
                        SelloButton(
                          label: 'Clear Local Cache',
                          icon: Icons.cleaning_services_outlined,
                          variant: SelloButtonVariant.outline,
                          loading: dev.isBusy,
                          onPressed: () => ref
                              .read(devExperienceProvider.notifier)
                              .clearLocalCache(),
                        ),
                        SelloButton(
                          label: 'Logout',
                          icon: Icons.logout_rounded,
                          variant: SelloButtonVariant.outline,
                          loading: dev.isBusy,
                          onPressed:
                              auth.isAuthenticated || auth.isAuthenticating
                                  ? () async {
                                      await ref
                                          .read(devExperienceProvider.notifier)
                                          .logout();
                                      if (context.mounted) {
                                        Navigator.of(context).maybePop();
                                      }
                                    }
                                  : null,
                        ),
                      ],
                    ),
                    if (dev.lastMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        dev.lastMessage!,
                        style: context.texts.bodySmall?.copyWith(
                          color: context.selloColors.textSecondary,
                        ),
                      ),
                    ],
                    const Divider(height: AppSpacing.xl),
                    Text('Current Context', style: context.texts.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    _ContextRow(label: 'Auth status', value: auth.status.name),
                    _ContextRow(
                      label: 'Company',
                      value: session == null
                          ? '-'
                          : '${session.company.name}\n${session.company.id}',
                    ),
                    _ContextRow(
                      label: 'Branch',
                      value: session?.branch == null
                          ? '-'
                          : '${session!.branch!.name}\n${session.branch!.id}',
                    ),
                    _ContextRow(
                      label: 'Employee',
                      value: session == null
                          ? '-'
                          : '${session.employee.fullName}\n${session.employee.id}',
                    ),
                    _ContextRow(
                      label: 'Role',
                      value: session?.role.name ?? '-',
                    ),
                    _ContextRow(
                      label: 'Subscription',
                      value: session == null
                          ? '-'
                          : '${session.company.plan} · ${session.company.subscriptionStatus}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: context.texts.labelMedium?.copyWith(
                color: context.selloColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: context.texts.bodyMedium),
          ),
        ],
      ),
    );
  }
}
