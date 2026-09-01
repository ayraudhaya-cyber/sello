import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Hub Settings → Branding. Shown only when the tenant is entitled and the
/// signed-in user can edit business settings.
class BrandingSettingsSection extends ConsumerStatefulWidget {
  const BrandingSettingsSection({super.key});

  @override
  ConsumerState<BrandingSettingsSection> createState() =>
      _BrandingSettingsSectionState();
}

class _BrandingSettingsSectionState
    extends ConsumerState<BrandingSettingsSection> {
  final _hex = TextEditingController();
  final _navHex = TextEditingController();
  final _media = MediaService();
  ProcessedMedia? _pendingLogo;
  ProcessedMedia? _pendingLight;
  bool _clearLogo = false;
  bool _clearLight = false;
  bool _pickingDark = false;
  bool _pickingLight = false;
  String? _hexError;
  String? _navHexError;
  String? _lastSyncedColor;
  String? _lastSyncedNavColor;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(hubSettingsProvider).settings;
    final color = settings?.primaryColor;
    final nav = settings?.navBackgroundColor;
    _hex.text = color ?? '';
    _navHex.text = nav ?? '';
    _lastSyncedColor = color;
    _lastSyncedNavColor = nav;
  }

  @override
  void dispose() {
    _hex.dispose();
    _navHex.dispose();
    super.dispose();
  }

  void _syncFromSettings(String? color, String? navColor) {
    if (color == _lastSyncedColor && navColor == _lastSyncedNavColor) return;
    _lastSyncedColor = color;
    _lastSyncedNavColor = navColor;
    final next = color ?? '';
    final nextNav = navColor ?? '';
    if (_hex.text != next) {
      _hex.text = next;
    }
    if (_navHex.text != nextNav) {
      _navHex.text = nextNav;
    }
    if (mounted) setState(() {});
  }

  bool _isDirty(String? savedColor, String? savedNavColor) {
    if (_pendingLogo != null ||
        _pendingLight != null ||
        _clearLogo ||
        _clearLight) {
      return true;
    }
    return ClientBranding.normalizeHex(_hex.text) !=
            ClientBranding.normalizeHex(savedColor) ||
        ClientBranding.normalizeHex(_navHex.text) !=
            ClientBranding.normalizeHex(savedNavColor);
  }

  Future<void> _pickLogo({required bool light}) async {
    setState(() {
      if (light) {
        _pickingLight = true;
      } else {
        _pickingDark = true;
      }
    });
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
        if (light) {
          _pendingLight = prepared;
          _clearLight = false;
        } else {
          _pendingLogo = prepared;
          _clearLogo = false;
        }
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
      if (mounted) {
        setState(() {
          _pickingDark = false;
          _pickingLight = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final hex = _hex.text.trim();
    final navHex = _navHex.text.trim();
    var hexError = hex.isNotEmpty && ClientBranding.normalizeHex(hex) == null
        ? 'Enter a colour as #RRGGBB.'
        : null;
    var navError =
        navHex.isNotEmpty && ClientBranding.normalizeHex(navHex) == null
        ? 'Enter a colour as #RRGGBB.'
        : null;
    if (hexError != null || navError != null) {
      setState(() {
        _hexError = hexError;
        _navHexError = navError;
      });
      return;
    }
    setState(() {
      _hexError = null;
      _navHexError = null;
    });

    final error = await ref
        .read(hubSettingsProvider.notifier)
        .saveBranding(
          logo: _pendingLogo,
          logoLight: _pendingLight,
          clearLogo: _clearLogo,
          clearLogoLight: _clearLight,
          primaryColor: hex,
          navBackgroundColor: navHex,
        );
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    setState(() {
      _pendingLogo = null;
      _pendingLight = null;
      _clearLogo = false;
      _clearLight = false;
    });
    SelloSnackbars.success(context, 'Branding saved');
  }

  void _discard(String? savedColor, String? savedNavColor) {
    setState(() {
      _pendingLogo = null;
      _pendingLight = null;
      _clearLogo = false;
      _clearLight = false;
      _hex.text = savedColor ?? '';
      _navHex.text = savedNavColor ?? '';
      _hexError = null;
      _navHexError = null;
    });
  }

  bool _canResetToSello(CompanySettings? saved) {
    if (_pendingLogo != null || _pendingLight != null) return true;
    if (_hex.text.trim().isNotEmpty || _navHex.text.trim().isNotEmpty) {
      return true;
    }
    if (saved?.logoUrl != null && !_clearLogo) return true;
    if (saved?.logoLightUrl != null && !_clearLight) return true;
    return false;
  }

  void _resetToSello(CompanySettings? saved) {
    setState(() {
      _pendingLogo = null;
      _pendingLight = null;
      _clearLogo = saved?.logoUrl != null;
      _clearLight = saved?.logoLightUrl != null;
      _hex.clear();
      _navHex.clear();
      _hexError = null;
      _navHexError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allowed = ref.watch(canAccessBrandingSettingsProvider);
    final state = ref.watch(hubSettingsProvider);
    final saved = state.settings;

    ref.listen(hubSettingsProvider, (previous, next) {
      final color = next.settings?.primaryColor;
      final navColor = next.settings?.navBackgroundColor;
      if (color == _lastSyncedColor && navColor == _lastSyncedNavColor) {
        return;
      }
      if (_pendingLogo != null ||
          _pendingLight != null ||
          _clearLogo ||
          _clearLight) {
        return;
      }
      _syncFromSettings(color, navColor);
    });

    if (!allowed) return const SizedBox.shrink();

    final draftHex = _hex.text.trim();
    final previewColor = draftHex.isEmpty
        ? null
        : ClientBranding.normalizeHex(draftHex);
    final draftNavHex = _navHex.text.trim();
    final previewNav = draftNavHex.isEmpty
        ? null
        : ClientBranding.normalizeHex(draftNavHex);
    final previewLogo = _clearLogo
        ? null
        : (_pendingLogo == null ? saved?.logoUrl : null);
    final previewLight = _clearLight
        ? null
        : (_pendingLight == null ? saved?.logoLightUrl : null);
    final preview = ClientBranding.resolve(
      logoUrl: previewLogo,
      logoLightUrl: previewLight,
      primaryColor: previewColor,
      navBackgroundColor: previewNav,
    );
    final dirty = _isDirty(saved?.primaryColor, saved?.navBackgroundColor);
    final saving = state.isSavingBranding;

    return SettingsSectionScaffold(
      actionBar: SettingsActionBar(
        enabled: dirty,
        saving: saving,
        onSave: _save,
        onDiscard: () =>
            _discard(saved?.primaryColor, saved?.navBackgroundColor),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroupCard(
            title: 'Brand assets',
            description:
                'Two logos — one for dark chrome, one for light pages.',
            child: SettingsTwoUp(
              spacing: 16,
              children: [
                _LogoTile(
                  title: 'Dark surface logo',
                  helper: 'Shown on dark backgrounds.',
                  bytes: _clearLogo ? null : _pendingLogo?.bytes,
                  url: _clearLogo ? null : saved?.logoUrl,
                  branding: preview,
                  loading: _pickingDark,
                  darkSurface: true,
                  saving: saving,
                  onUpload: () => _pickLogo(light: false),
                ),
                _LogoTile(
                  title: 'Light surface logo',
                  helper: 'Shown on light backgrounds.',
                  bytes: _clearLight ? null : _pendingLight?.bytes,
                  url: _clearLight ? null : saved?.logoLightUrl,
                  branding: preview,
                  loading: _pickingLight,
                  darkSurface: false,
                  onLightSurface: true,
                  saving: saving,
                  onUpload: () => _pickLogo(light: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsGroupCard(
            title: 'Brand colours',
            description:
                'These tint branded accents and the sidebar. Status colours stay Sello.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTwoUp(
                  spacing: 16,
                  children: [
                    SettingsCompactField(
                      label: 'Accent colour',
                      helper: 'Buttons, tabs, and selected navigation.',
                      child: SelloColorField(
                        controller: _hex,
                        hint: '#6C4FF2',
                        fallbackColor: AppColors.primary,
                        errorText: _hexError,
                        enabled: !saving,
                        onChanged: (_) => setState(() => _hexError = null),
                      ),
                    ),
                    SettingsCompactField(
                      label: 'Sidebar colour',
                      helper: 'Hub sidebar and branded splash.',
                      child: SelloColorField(
                        controller: _navHex,
                        hint: '#1A1530',
                        fallbackColor: preview.navTop,
                        errorText: _navHexError,
                        enabled: !saving,
                        onChanged: (_) => setState(() => _navHexError = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelloButton(
                    label: 'Reset to Sello theme',
                    variant: SelloButtonVariant.ghost,
                    size: SelloButtonSize.small,
                    onPressed: _canResetToSello(saved) && !saving
                        ? () => _resetToSello(saved)
                        : null,
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

class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.title,
    required this.helper,
    this.bytes,
    this.url,
    this.branding,
    required this.loading,
    required this.darkSurface,
    this.onLightSurface = false,
    required this.saving,
    required this.onUpload,
  });

  final String title;
  final String helper;
  final Uint8List? bytes;
  final String? url;
  final ClientBranding? branding;
  final bool loading;
  final bool darkSurface;
  final bool onLightSurface;
  final bool saving;
  final VoidCallback onUpload;

  bool get _hasCustomLogo =>
      (bytes != null && bytes!.isNotEmpty) || (url != null && url!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloFieldLabel(label: title, hint: helper),
        const SizedBox(height: 10),
        Theme(
          data: AppTheme.themed(branding ?? ClientBranding.sello),
          child: _LogoSurface(
            bytes: bytes,
            url: url,
            branding: branding,
            loading: loading,
            darkSurface: darkSurface,
            onLightSurface: onLightSurface,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: SelloButton(
            label: _hasCustomLogo ? 'Replace logo' : 'Upload logo',
            variant: SelloButtonVariant.secondary,
            size: SelloButtonSize.small,
            loading: loading,
            onPressed: saving || loading ? null : onUpload,
          ),
        ),
      ],
    );
  }
}

/// Constrained contain-preview — never a square crop, never stretched.
class _LogoSurface extends StatelessWidget {
  const _LogoSurface({
    this.bytes,
    this.url,
    this.branding,
    required this.loading,
    required this.darkSurface,
    this.onLightSurface = false,
  });

  final Uint8List? bytes;
  final String? url;
  final ClientBranding? branding;
  final bool loading;
  final bool darkSurface;
  final bool onLightSurface;

  static const _maxLogoHeight = 40.0;
  static const _maxLogoWidth = 240.0;
  static const _panelHeight = 80.0;

  @override
  Widget build(BuildContext context) {
    final logo = Align(
      alignment: Alignment.centerLeft,
      child: BrandedLogo(
        size: _maxLogoHeight,
        maxWidth: _maxLogoWidth,
        bytes: bytes,
        branding:
            branding ??
            ClientBranding.resolve(
              logoUrl: onLightSurface ? null : url,
              logoLightUrl: onLightSurface ? url : null,
            ),
        onLightSurface: onLightSurface,
      ),
    );

    final panel = darkSurface
        ? BrandedDarkSurface(
            borderRadius: AppRadius.controlAll,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: SizedBox(
              height: _maxLogoHeight,
              width: double.infinity,
              child: logo,
            ),
          )
        : Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: AppColors.outlinePanel),
            ),
            child: SizedBox(
              height: _maxLogoHeight,
              width: double.infinity,
              child: logo,
            ),
          );

    return SizedBox(
      height: _panelHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          panel,
          if (loading)
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.72),
                borderRadius: AppRadius.controlAll,
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
