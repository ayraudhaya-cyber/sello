import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/company_settings_repository.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/providers/branding_provider.dart';

class HubSettingsState {
  const HubSettingsState({
    this.settings,
    this.draft,
    this.isLoading = false,
    this.isSaving = false,
    this.isSavingBranding = false,
    this.errorMessage,
    this.initialized = false,
  });

  final CompanySettings? settings;
  /// Local edits awaiting save. Mirrors [settings] when clean.
  final CompanySettings? draft;
  final bool isLoading;
  final bool isSaving;
  final bool isSavingBranding;
  final String? errorMessage;
  final bool initialized;

  bool get isDirty {
    final current = settings;
    final next = draft;
    if (current == null || next == null) return false;
    return current != next;
  }

  CompanySettings get effective =>
      draft ?? settings ?? CompanySettings.defaults;

  HubSettingsState copyWith({
    CompanySettings? settings,
    CompanySettings? draft,
    bool? isLoading,
    bool? isSaving,
    bool? isSavingBranding,
    String? errorMessage,
    bool? initialized,
    bool clearError = false,
    bool clearDraft = false,
  }) {
    return HubSettingsState(
      settings: settings ?? this.settings,
      draft: clearDraft ? (settings ?? this.settings) : (draft ?? this.draft),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isSavingBranding: isSavingBranding ?? this.isSavingBranding,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

class HubSettingsNotifier extends Notifier<HubSettingsState> {
  CompanySettingsRepository get _repo =>
      ref.read(companySettingsRepositoryProvider);

  @override
  HubSettingsState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(load);
    });

    Future.microtask(load);
    return const HubSettingsState(isLoading: true);
  }

  Future<void> load() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      // Session may still be bootstrapping after a deep-link refresh.
      state = state.copyWith(isLoading: true, clearError: true);
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final settings = await _repo.fetchForCompany(
        session.company.id,
        employeeId: session.employee.id,
      );
      state = HubSettingsState(
        settings: settings,
        draft: settings,
        isLoading: false,
        initialized: true,
      );
    } on AppFailure catch (failure) {
      state = HubSettingsState(
        isLoading: false,
        initialized: true,
        errorMessage: failure.message,
      );
    }
  }

  void patchDraft(CompanySettings Function(CompanySettings current) update) {
    final current = state.effective;
    state = state.copyWith(draft: update(current), clearError: true);
  }

  void discardDraft() {
    state = state.copyWith(clearDraft: true, clearError: true);
  }

  Future<String?> save() async {
    final session = ref.read(currentSessionProvider);
    final draft = state.draft;
    if (session == null) return 'No active session found.';
    if (draft == null) return 'Settings are not loaded yet.';
    if (!state.isDirty) return null;

    if (draft.smsSenderIdEditable) {
      final next = draft.smsSenderId;
      final changed = next != state.settings?.smsSenderId;
      if (changed && SmsSenderId.normalize(next) == null) {
        return 'Enter a valid SMS Sender ID (3 to 11 letters or digits).';
      }
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final saved = await _repo.updateSettings(
        settings: draft,
        employeeId: session.employee.id,
      );
      state = state.copyWith(
        settings: saved,
        draft: saved,
        isSaving: false,
        clearError: true,
      );
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: failure.message,
      );
      return failure.message;
    }
  }

  Future<String?> saveBranding({
    ProcessedMedia? logo,
    ProcessedMedia? logoLight,
    required bool clearLogo,
    required bool clearLogoLight,
    required String? primaryColor,
    required String? navBackgroundColor,
  }) async {
    final session = ref.read(currentSessionProvider);
    final permissions = ref.read(permissionServiceProvider);
    final current = state.settings;
    if (session == null) return 'No active session found.';
    if (current == null) return 'Settings are not loaded yet.';
    if (permissions == null ||
        !permissions.canAccessBrandingSettings(current.customBrandingEnabled)) {
      return 'Branding is not available for this business.';
    }

    final hex = primaryColor?.trim() ?? '';
    final normalized = hex.isEmpty ? null : ClientBranding.normalizeHex(hex);
    if (hex.isNotEmpty && normalized == null) {
      return 'Enter a colour as #RRGGBB.';
    }

    final navHex = navBackgroundColor?.trim() ?? '';
    final normalizedNav =
        navHex.isEmpty ? null : ClientBranding.normalizeHex(navHex);
    if (navHex.isNotEmpty && normalizedNav == null) {
      return 'Enter a colour as #RRGGBB.';
    }

    state = state.copyWith(isSavingBranding: true, clearError: true);
    try {
      var nextLogo = current.logoUrl;
      var nextLight = current.logoLightUrl;
      if (clearLogo) {
        await _repo.removeLogo(companyId: session.company.id);
        nextLogo = null;
      } else if (logo != null) {
        nextLogo = await _repo.uploadLogo(
          companyId: session.company.id,
          media: logo,
        );
      }
      if (clearLogoLight) {
        await _repo.removeLogo(companyId: session.company.id, light: true);
        nextLight = null;
      } else if (logoLight != null) {
        nextLight = await _repo.uploadLogo(
          companyId: session.company.id,
          media: logoLight,
          light: true,
        );
      }

      final saved = await _repo.updateBranding(
        companyId: session.company.id,
        employeeId: session.employee.id,
        logoUrl: nextLogo,
        logoLightUrl: nextLight,
        primaryColor: normalized,
        navBackgroundColor: normalizedNav,
      );

      final draft = state.draft;
      state = state.copyWith(
        settings: saved,
        draft: draft == null
            ? saved
            : draft.copyWith(
                logoUrl: saved.logoUrl,
                logoLightUrl: saved.logoLightUrl,
                primaryColor: saved.primaryColor,
                navBackgroundColor: saved.navBackgroundColor,
                clearLogoUrl: saved.logoUrl == null,
                clearLogoLightUrl: saved.logoLightUrl == null,
                clearPrimaryColor: saved.primaryColor == null,
                clearNavBackgroundColor: saved.navBackgroundColor == null,
              ),
        isSavingBranding: false,
        clearError: true,
      );
      await ref.read(brandingProvider.notifier).refresh();
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isSavingBranding: false,
        errorMessage: failure.message,
      );
      return failure.message;
    } catch (_) {
      state = state.copyWith(
        isSavingBranding: false,
        errorMessage: 'Unable to save branding.',
      );
      return 'Unable to save branding.';
    }
  }

  /// Business logo + document name toggle (all entitled settings editors).
  Future<String?> saveDocumentIdentity({
    ProcessedMedia? logo,
    required bool clearLogo,
    required bool showBusinessNameWithLogo,
  }) async {
    final session = ref.read(currentSessionProvider);
    final permissions = ref.read(permissionServiceProvider);
    final current = state.settings;
    if (session == null) return 'No active session found.';
    if (current == null) return 'Settings are not loaded yet.';
    if (permissions == null || !permissions.canManageCompanyLogo) {
      return 'You do not have permission to update the business logo.';
    }

    state = state.copyWith(isSavingBranding: true, clearError: true);
    try {
      var nextLight = current.logoLightUrl;
      var nextDark = current.logoUrl;

      if (clearLogo) {
        if (current.logoLightUrl != null) {
          await _repo.removeLogo(companyId: session.company.id, light: true);
          nextLight = null;
        } else if (current.logoUrl != null) {
          // Document was falling back to the dark logo — clear it.
          await _repo.removeLogo(companyId: session.company.id);
          nextDark = null;
        }
      } else if (logo != null) {
        nextLight = await _repo.uploadLogo(
          companyId: session.company.id,
          media: logo,
          light: true,
        );
        nextDark = current.logoUrl ?? nextLight;
      }

      final saved = await _repo.updateDocumentIdentity(
        companyId: session.company.id,
        employeeId: session.employee.id,
        logoUrl: nextDark,
        logoLightUrl: nextLight,
        showBusinessNameWithLogo: showBusinessNameWithLogo,
      );

      final draft = state.draft;
      state = state.copyWith(
        settings: saved,
        draft: draft == null
            ? saved
            : draft.copyWith(
                logoUrl: saved.logoUrl,
                logoLightUrl: saved.logoLightUrl,
                documentShowBusinessNameWithLogo:
                    saved.documentShowBusinessNameWithLogo,
                clearLogoUrl: saved.logoUrl == null,
                clearLogoLightUrl: saved.logoLightUrl == null,
              ),
        isSavingBranding: false,
        clearError: true,
      );
      await ref.read(brandingProvider.notifier).refresh();
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isSavingBranding: false,
        errorMessage: failure.message,
      );
      return failure.message;
    } catch (_) {
      state = state.copyWith(
        isSavingBranding: false,
        errorMessage: 'Unable to save document identity.',
      );
      return 'Unable to save document identity.';
    }
  }
}

final hubSettingsProvider =
    NotifierProvider<HubSettingsNotifier, HubSettingsState>(
  HubSettingsNotifier.new,
);

/// Convenience read of persisted settings (falls back to defaults).
final companySettingsProvider = Provider<CompanySettings>((ref) {
  final state = ref.watch(hubSettingsProvider);
  return state.settings ?? CompanySettings.defaults;
});

/// Branding settings entry: settings edit + tenant entitlement.
final canAccessBrandingSettingsProvider = Provider<bool>((ref) {
  final permissions = ref.watch(permissionServiceProvider);
  final enabled =
      ref.watch(hubSettingsProvider).settings?.customBrandingEnabled ?? false;
  return permissions?.canAccessBrandingSettings(enabled) ?? false;
});
