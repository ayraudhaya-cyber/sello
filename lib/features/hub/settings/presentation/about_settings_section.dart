import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/services/updates/update_check_messages.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings → About — installed version and a quiet update check.
class AboutSettingsSection extends ConsumerWidget {
  const AboutSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedAppVersionProvider);
    final check = ref.watch(updateCheckControllerProvider);
    final snapshot = check.valueOrNull;
    final checking = check.isLoading;

    return SettingsGroupCard(
      title: 'About Sello',
      description: 'Version information for this installation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTwoColumn(
            gap: 12,
            children: [
              _AboutMetric(
                label: 'Version',
                value: installed.when(
                  data: (v) => v.versionName,
                  loading: () => '…',
                  error: (_, _) => '—',
                ),
                helper: 'Taken from this installed app, not the server.',
              ),
              _AboutMetric(
                label: 'Build',
                value: installed.when(
                  data: (v) => '${v.build}',
                  loading: () => '…',
                  error: (_, _) => '—',
                ),
              ),
              _AboutMetric(
                label: 'Status',
                value: _statusLabel(snapshot, checking: checking),
              ),
              _AboutMetric(
                label: 'Latest',
                value: snapshot?.latest?.versionName ?? '—',
                helper: snapshot?.releasedAt == null
                    ? null
                    : 'Released ${SelloFormatters.date(snapshot!.releasedAt)}.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: SelloButton(
              label: checking ? 'Checking…' : 'Check for updates',
              icon: Icons.refresh_rounded,
              variant: SelloButtonVariant.secondary,
              onPressed: checking ? null : () => _checkNow(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(UpdateCheckSnapshot? snapshot, {required bool checking}) {
    if (checking && snapshot == null) return 'Checking';
    if (snapshot == null) return 'Not checked';
    return switch (snapshot.status) {
      UpdateCheckStatus.upToDate => 'Up to date',
      UpdateCheckStatus.updateAvailable => 'Update available',
      UpdateCheckStatus.updateRequired => 'Update required',
      UpdateCheckStatus.checkFailed => 'Couldn’t check',
    };
  }

  Future<void> _checkNow(BuildContext context, WidgetRef ref) async {
    final result =
        await ref.read(updateCheckControllerProvider.notifier).checkNow();
    if (!context.mounted) return;
    if (result.status == UpdateCheckStatus.upToDate) {
      SelloSnackbars.success(
        context,
        UpdateCheckMessages.manualResult(result),
      );
    } else if (result.status == UpdateCheckStatus.checkFailed) {
      SelloSnackbars.info(
        context,
        UpdateCheckMessages.manualResult(result),
      );
    }
  }
}

class _AboutMetric extends StatelessWidget {
  const _AboutMetric({
    required this.label,
    required this.value,
    this.helper,
  });

  final String label;
  final String value;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelloFieldLabel(label: label, hint: helper),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
