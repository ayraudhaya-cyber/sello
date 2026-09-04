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

/// Business logo + contact block for invoices/receipts — all tenants.
///
/// Not gated by Custom Branding. Uses `document_*` columns only.
class DocumentIdentitySettingsSection extends ConsumerStatefulWidget {
  const DocumentIdentitySettingsSection({super.key});

  @override
  ConsumerState<DocumentIdentitySettingsSection> createState() =>
      _DocumentIdentitySettingsSectionState();
}

class _DocumentIdentitySettingsSectionState
    extends ConsumerState<DocumentIdentitySettingsSection> {
  final _media = MediaService();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _termsController = TextEditingController();

  ProcessedMedia? _pendingLogo;
  bool _clearLogo = false;
  bool _picking = false;
  bool? _showNameWithLogo;
  var _hydrated = false;
  String? _hydratedSettingsId;

  @override
  void dispose() {
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  void _hydrateFromSaved({
    required String settingsId,
    required String? address,
    required String? phone,
    required String? email,
    required String? terms,
  }) {
    if (_hydrated && _hydratedSettingsId == settingsId) return;
    _addressController.text = address ?? '';
    _phoneController.text = phone ?? '';
    _emailController.text = email ?? '';
    _termsController.text = terms ?? '';
    _hydrated = true;
    _hydratedSettingsId = settingsId;
  }

  bool _isDirty({
    required bool savedShowName,
    required String? savedAddress,
    required String? savedPhone,
    required String? savedEmail,
    required String? savedTerms,
  }) {
    if (_pendingLogo != null || _clearLogo) return true;
    final show = _showNameWithLogo ?? savedShowName;
    if (show != savedShowName) return true;
    if (_addressController.text.trim() != (savedAddress ?? '').trim()) {
      return true;
    }
    if (_phoneController.text.trim() != (savedPhone ?? '').trim()) return true;
    if (_emailController.text.trim() != (savedEmail ?? '').trim()) return true;
    if (_termsController.text.trim() != (savedTerms ?? '').trim()) return true;
    return false;
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

  Future<void> _save({
    required bool savedShowName,
  }) async {
    final error = await ref.read(hubSettingsProvider.notifier).saveDocumentIdentity(
          logo: _pendingLogo,
          clearLogo: _clearLogo,
          showBusinessNameWithLogo: _showNameWithLogo ?? savedShowName,
          documentAddress: _addressController.text,
          documentPhone: _phoneController.text,
          documentEmail: _emailController.text,
          documentTerms: _termsController.text,
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
      _hydrated = false;
    });
    SelloSnackbars.success(context, 'Document identity saved.');
  }

  void _discard({
    required String? savedAddress,
    required String? savedPhone,
    required String? savedEmail,
    required String? savedTerms,
  }) {
    setState(() {
      _pendingLogo = null;
      _clearLogo = false;
      _showNameWithLogo = null;
      _addressController.text = savedAddress ?? '';
      _phoneController.text = savedPhone ?? '';
      _emailController.text = savedEmail ?? '';
      _termsController.text = savedTerms ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubSettingsProvider);
    final permissions = ref.watch(permissionServiceProvider);
    final canEdit = permissions?.canManageCompanyLogo ?? false;
    final saved = state.settings;
    final savedShow = saved?.documentShowBusinessNameWithLogo ?? false;
    final savedAddress = saved?.documentAddress;
    final savedPhone = saved?.documentPhone;
    final savedEmail = saved?.documentEmail;
    final savedTerms = saved?.documentTerms;

    if (saved != null) {
      _hydrateFromSaved(
        settingsId: saved.id,
        address: savedAddress,
        phone: savedPhone,
        email: savedEmail,
        terms: savedTerms,
      );
    }

    final previewUrl = _clearLogo
        ? null
        : (_pendingLogo == null
            ? DocumentIssuerIdentity.resolveLogoUrl(saved?.documentLogoUrl)
            : null);
    final showName = _showNameWithLogo ?? savedShow;
    final hasLogo = _pendingLogo != null || (!_clearLogo && previewUrl != null);
    final dirty = _isDirty(
      savedShowName: savedShow,
      savedAddress: savedAddress,
      savedPhone: savedPhone,
      savedEmail: savedEmail,
      savedTerms: savedTerms,
    );
    final saving = state.isSavingBranding;

    return SettingsGroupCard(
      title: 'Invoices & Receipts',
      description:
          'Choose how your business appears on invoices and receipts sent to customers.',
      footer: canEdit && dirty
          ? SettingsActionBar(
              enabled: dirty,
              saving: saving,
              onSave: () => _save(savedShowName: savedShow),
              onDiscard: () => _discard(
                savedAddress: savedAddress,
                savedPhone: savedPhone,
                savedEmail: savedEmail,
                savedTerms: savedTerms,
              ),
            )
          : null,
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
          const SizedBox(height: 20),
          SettingsSubgroup(
            title: 'Contact on documents',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsCompactField(
                  label: 'Address',
                  child: SelloTextField(
                    controller: _addressController,
                    hint: 'Street, city, postal code',
                    maxLines: 3,
                    enabled: canEdit && !saving,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                SettingsTwoUp(
                  children: [
                    SettingsCompactField(
                      label: 'Contact number',
                      child: SelloTextField(
                        controller: _phoneController,
                        hint: '+94 …',
                        keyboardType: TextInputType.phone,
                        enabled: canEdit && !saving,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SettingsCompactField(
                      label: 'Email',
                      child: SelloTextField(
                        controller: _emailController,
                        hint: 'hello@business.com',
                        keyboardType: TextInputType.emailAddress,
                        enabled: canEdit && !saving,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SettingsCompactField(
            label: 'Terms',
            helper: 'Shown at the bottom of invoices and receipts.',
            child: SelloTextField(
              controller: _termsController,
              hint: 'Payment terms, return policy, or thank-you note',
              maxLines: 5,
              enabled: canEdit && !saving,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
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
