import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/updates/sello_build_meta.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';

/// Quiet product identity lines for Settings → About and Sales Profile.
///
/// Version/build always come from [installedAppVersionProvider] (`pubspec.yaml`
/// via `package_info_plus`). Optional revision is compile-time only.
class SelloAppInfoPanel extends ConsumerWidget {
  const SelloAppInfoPanel({
    super.key,
    this.compact = false,
  });

  /// When true, uses a denser list suitable for Sales Profile cards.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedAppVersionProvider);
    final revision = SelloBuildMeta.shortRevision;

    final versionLabel = installed.when(
      data: (v) => v.versionName,
      loading: () => '…',
      error: (_, _) => '—',
    );
    final buildLabel = installed.when(
      data: (v) => '${v.build}',
      loading: () => '…',
      error: (_, _) => '—',
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sello',
            style: context.texts.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Version $versionLabel · Build $buildLabel'
            '${revision == null ? '' : ' · $revision'}',
            style: context.texts.bodySmall?.copyWith(
              color: context.selloColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sello is updated regularly with improvements for your business.',
            style: context.texts.bodySmall?.copyWith(
              color: context.selloColors.textFaint,
              height: 1.35,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow(label: 'Product', value: 'Sello'),
        const SizedBox(height: 12),
        _InfoRow(label: 'Version', value: versionLabel),
        const SizedBox(height: 12),
        _InfoRow(label: 'Build', value: buildLabel),
        if (revision != null) ...[
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Revision',
            value: revision,
            helper: 'Deployment identifier for support.',
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
      crossAxisAlignment: CrossAxisAlignment.start,
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

/// Formats an [AppVersion] for tests and diagnostics (not for UI copy).
String formatInstalledVersionLine(AppVersion version, {String? revision}) {
  final base = 'Sello ${version.versionName} (build ${version.build})';
  if (revision == null || revision.isEmpty) return base;
  return '$base · $revision';
}
