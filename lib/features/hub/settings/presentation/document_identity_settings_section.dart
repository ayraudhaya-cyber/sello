import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Business logo + invoice/receipt name option — available to all tenants.
///
/// Not gated by Custom Branding. Uses `logo_light_url` (fallback `logo_url`).
class DocumentIdentitySettingsSection extends ConsumerStatefulWidget {
  const DocumentIdentitySettingsSection({super.key});

  @override
  ConsumerState<DocumentIdentitySettingsSection> createState() =>
      _DocumentIdentitySettingsSectionState();
}

class _DocumentIdentitySettingsSectionState
    extends ConsumerState<DocumentIdentitySettingsSection> {
  final _media = MediaService();
  ProcessedMedia? _pendingLogo;
  bool _clearLogo = false;
  bool _picking = false;
  bool? _showNameWithLogo;

  bool _isDirty(bool savedShowName, String? savedLight, String? savedDark) {
    if (_pendingLogo != null || _clearLogo) return true;
    final show = _showNameWithLogo ?? savedShowName;
    return show != savedShowName;
  }

  Future<void> _pickLogo() async {
    setState(() => _picking = true);
    try {
      final file = await _media.pickWithBestExperience(context);
      if (file == null || !mounted) return;
      final raw = await file.readAsBytes();
      if (!mounted) return;
      final prepared = await _media.prepareForUpload(
        context,
        raw,
        offerCrop: false,
        preferPng: true,
      );
      if (prepared == null || !mounted) return;
      setState(() {
        _pendingLogo = prepared;
        _clearLogo = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.error(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(
        context,
        'Unable to use that image. Try PNG or JPG.',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save(bool savedShowName) async {
    final error = await ref.read(hubSettingsProvider.notifier).saveDocumentIdentity(
          logo: _pendingLogo,
          clearLogo: _clearLogo,
          showBusinessNameWithLogo: _showNameWithLogo ?? savedShowName,
        );
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    setState(() {
      _pendingLogo = null;
      _clearLogo = false;
      _showNameWithLogo = null;
    });
    SelloSnackbars.success(context, 'Document identity saved.');
  }

  void _discard() {
    setState(() {
      _pendingLogo = null;
      _clearLogo = false;
      _showNameWithLogo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubSettingsProvider);
    final permissions = ref.watch(permissionServiceProvider);
    final canEdit = permissions?.canManageCompanyLogo ?? false;
    final saved = state.settings;
    final savedShow = saved?.documentShowBusinessNameWithLogo ?? false;
    final previewUrl = _clearLogo
        ? null
        : (_pendingLogo == null
            ? DocumentIssuerIdentity.resolveLogoUrl(
                logoLightUrl: saved?.logoLightUrl,
                logoUrl: saved?.logoUrl,
              )
            : null);
    final showName = _showNameWithLogo ?? savedShow;
    final hasLogo = _pendingLogo != null || (!_clearLogo && previewUrl != null);
    final dirty = _isDirty(savedShow, saved?.logoLightUrl, saved?.logoUrl);
    final saving = state.isSavingBranding;

    return SettingsSectionScaffold(
      actionBar: canEdit
          ? SettingsActionBar(
              enabled: dirty,
              saving: saving,
              onSave: () => _save(savedShow),
              onDiscard: _discard,
            )
          : null,
      body: SettingsGroupCard(
        title: 'Customer documents',
        description:
            'How your business appears on invoices and receipts. '
            'Does not require Custom Branding.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsCompactField(
              label: 'Business logo',
              helper:
                  'Shown on light invoice and receipt pages. '
                  'If empty, your business name is used.',
              child: _LogoPreview(
                bytes: _clearLogo ? null : _pendingLogo?.bytes,
                url: previewUrl,
                loading: _picking,
                saving: saving,
                enabled: canEdit,
                onUpload: _pickLogo,
                onClear: hasLogo && canEdit
                    ? () => setState(() {
                          _clearLogo = true;
                          _pendingLogo = null;
                        })
                    : null,
              ),
            ),
            if (hasLogo) ...[
              const SizedBox(height: 16),
              SelloStatusToggle(
                value: showName,
                label: 'Show business name with logo',
                helper:
                    'Off shows the logo only. On shows your business name under the logo.',
                onChanged: (value) {
                  if (!canEdit || saving) return;
                  setState(() => _showNameWithLogo = value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({
    required this.bytes,
    required this.url,
    required this.loading,
    required this.saving,
    required this.enabled,
    required this.onUpload,
    this.onClear,
  });

  final Uint8List? bytes;
  final String? url;
  final bool loading;
  final bool saving;
  final bool enabled;
  final VoidCallback onUpload;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasImage = bytes != null || (url != null && url!.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 88,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: AppColors.outlinePanel),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : hasImage
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 200,
                        maxHeight: 56,
                      ),
                      child: bytes != null
                          ? Image.memory(bytes!, fit: BoxFit.contain)
                          : Image.network(url!, fit: BoxFit.contain),
                    )
                  : Text(
                      'No logo yet — invoices will show your business name.',
                      style: context.texts.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SelloButton(
              label: hasImage ? 'Replace logo' : 'Upload logo',
              icon: Icons.upload_rounded,
              variant: SelloButtonVariant.secondary,
              size: SelloButtonSize.small,
              loading: loading || saving,
              onPressed: enabled && !saving && !loading ? onUpload : null,
            ),
            if (onClear != null)
              SelloButton(
                label: 'Remove',
                variant: SelloButtonVariant.ghost,
                size: SelloButtonSize.small,
                onPressed: saving ? null : onClear,
              ),
          ],
        ),
      ],
    );
  }
}
