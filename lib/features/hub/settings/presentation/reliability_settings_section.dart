import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/services/reliability/reliability_providers.dart';
import 'package:sello/shared/models/reliability/backup_models.dart';
import 'package:sello/shared/models/reliability/connectivity_status.dart';
import 'package:sello/shared/models/reliability/reliability_diagnostics.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Settings → Reliability — confidence dashboard for sync & protection.
class ReliabilitySettingsSection extends ConsumerWidget {
  const ReliabilitySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reliabilityDiagnosticsProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => SettingsGroupCard(
        title: 'Reliability',
        child: Text(
          'Unable to load reliability status.',
          style: context.texts.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
      data: (diag) => _ReliabilityBody(diagnostics: diag),
    );
  }
}

class _ReliabilityBody extends ConsumerWidget {
  const _ReliabilityBody({required this.diagnostics});

  final ReliabilityDiagnostics diagnostics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = diagnostics;
    final fmt = DateFormat('MMM d · HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroupCard(
          title: 'Reliability',
          description:
              'Sello keeps your work safe — online or offline — and syncs '
              'when you reconnect.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusBanner(snapshot: diag.connectivity),
              const SizedBox(height: 18),
              SettingsTwoColumn(
                gap: 12,
                children: [
                  _MetricRow(
                    label: 'Sync health',
                    value: diag.syncHealthLabel,
                  ),
                  _MetricRow(
                    label: 'Pending sync',
                    value: '${diag.pendingSyncCount}',
                  ),
                  _MetricRow(
                    label: 'Last sync',
                    value: diag.lastSyncAt == null
                        ? 'Not yet'
                        : fmt.format(diag.lastSyncAt!.toLocal()),
                  ),
                  _MetricRow(
                    label: 'Backup',
                    value: diag.backupHealth.label,
                  ),
                  _MetricRow(
                    label: 'Last backup',
                    value: diag.lastSuccessfulBackup == null
                        ? 'Not yet'
                        : fmt.format(
                            (diag.lastSuccessfulBackup!.completedAt ??
                                    diag.lastSuccessfulBackup!.createdAt)
                                .toLocal(),
                          ),
                  ),
                  _MetricRow(
                    label: 'This device',
                    value: diag.deviceLabel ?? 'Ready',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  SelloButton(
                    label: 'Sync now',
                    icon: Icons.sync_rounded,
                    onPressed: () async {
                      await ref.read(syncEngineProvider).syncNow();
                      ref.invalidate(reliabilityDiagnosticsProvider);
                      if (!context.mounted) return;
                      SelloSnackbars.success(context, 'Sync finished.');
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SelloButton(
                    label: 'Create safeguard',
                    variant: SelloButtonVariant.secondary,
                    icon: Icons.shield_outlined,
                    onPressed: () async {
                      await ref
                          .read(backupServiceProvider)
                          .createManualBackup();
                      ref.invalidate(reliabilityDiagnosticsProvider);
                      if (!context.mounted) return;
                      SelloSnackbars.success(
                        context,
                        'Safeguard saved.',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroupCard(
          title: 'Pending sync items',
          description: diag.openSyncItems.isEmpty
              ? 'Nothing waiting — you are up to date.'
              : 'These changes will sync automatically when possible.',
          child: diag.openSyncItems.isEmpty
              ? Text(
                  'No pending work.',
                  style: context.texts.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < diag.openSyncItems.length; i++) ...[
                      if (i > 0) const Divider(height: 16),
                      _SyncItemRow(item: diag.openSyncItems[i]),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsGroupCard(
          title: 'Safeguard history',
          description:
              'Restore points you can return to later. Cloud restore expands '
              'in a future release.',
          child: diag.recentBackups.isEmpty
              ? Text(
                  'No safeguards yet — create one anytime.',
                  style: context.texts.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < diag.recentBackups.length; i++) ...[
                      if (i > 0) const Divider(height: 16),
                      _BackupRow(
                        record: diag.recentBackups[i],
                        onRestore: diag.recentBackups[i].isSuccessful
                            ? () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Restore this safeguard?'),
                                    content: const Text(
                                      'Your business will return to this '
                                      'point. Confirm only if you are sure.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Restore'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                final restore = ref.read(restoreServiceProvider);
                                final session = await restore
                                    .beginConfirm(diag.recentBackups[i].id);
                                await restore.runRestore(session.id);
                                ref.invalidate(reliabilityDiagnosticsProvider);
                                if (!context.mounted) return;
                                SelloSnackbars.success(
                                  context,
                                  'Restore complete.',
                                );
                              }
                            : null,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.snapshot});

  final ConnectivitySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final status = snapshot.status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.brandAccentContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Row(
        children: [
          Icon(
            switch (status) {
              ConnectivityStatus.online => Icons.cloud_done_outlined,
              ConnectivityStatus.offline => Icons.cloud_off_outlined,
              ConnectivityStatus.synchronizing => Icons.sync_rounded,
              ConnectivityStatus.syncFailed => Icons.sync_problem_rounded,
              ConnectivityStatus.waitingToSync => Icons.hourglass_top_rounded,
            },
            color: context.brandAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: context.texts.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.confidenceMessage,
                  style: context.texts.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
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

class _SyncItemRow extends StatelessWidget {
  const _SyncItemRow({required this.item});

  final SyncQueueItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.domain.label} · ${item.operation.name}',
                style: context.texts.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.status.label,
                style: context.texts.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          '#${item.sequence ?? '—'}',
          style: context.texts.labelSmall?.copyWith(
            color: AppColors.textFaint,
          ),
        ),
      ],
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({required this.record, this.onRestore});

  final BackupRecord record;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final when = record.completedAt ?? record.createdAt;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.label ?? record.kind.label,
                style: context.texts.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${record.kind.label} · ${record.status.label} · '
                '${DateFormat('MMM d · HH:mm').format(when.toLocal())}',
                style: context.texts.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (onRestore != null)
          TextButton(
            onPressed: onRestore,
            child: const Text('Restore'),
          ),
      ],
    );
  }
}
