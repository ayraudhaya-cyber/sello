import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/setup/owner_setup_service.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/models/team_invite_result.dart';
import 'package:sello/shared/providers/branding_provider.dart';

enum OwnerSetupStep { welcome, business, profile, team, sms, ready }

class AddedSalesRep {
  const AddedSalesRep({required this.fullName, required this.email});

  final String fullName;
  final String email;
}

class OwnerSetupState {
  const OwnerSetupState({
    this.step = OwnerSetupStep.welcome,
    this.isSaving = false,
    this.errorMessage,
    this.customBrandingEnabled = false,
    this.addedReps = const [],
    this.lastInvite,
    this.smsSenderId,
    this.smsSenderIdEditable = false,
    this.smsVerified = false,
  });

  final OwnerSetupStep step;
  final bool isSaving;
  final String? errorMessage;
  final bool customBrandingEnabled;
  final List<AddedSalesRep> addedReps;
  final TeamInviteResult? lastInvite;
  final String? smsSenderId;
  final bool smsSenderIdEditable;
  final bool smsVerified;

  bool get smsAlreadyConfigured => SmsSenderId.tryParse(smsSenderId) != null;

  bool get smsReady => smsVerified || smsAlreadyConfigured;

  OwnerSetupState copyWith({
    OwnerSetupStep? step,
    bool? isSaving,
    String? errorMessage,
    bool? customBrandingEnabled,
    List<AddedSalesRep>? addedReps,
    TeamInviteResult? lastInvite,
    String? smsSenderId,
    bool? smsSenderIdEditable,
    bool? smsVerified,
    bool clearError = false,
    bool clearInvite = false,
  }) {
    return OwnerSetupState(
      step: step ?? this.step,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      customBrandingEnabled:
          customBrandingEnabled ?? this.customBrandingEnabled,
      addedReps: addedReps ?? this.addedReps,
      lastInvite: clearInvite ? null : (lastInvite ?? this.lastInvite),
      smsSenderId: smsSenderId ?? this.smsSenderId,
      smsSenderIdEditable: smsSenderIdEditable ?? this.smsSenderIdEditable,
      smsVerified: smsVerified ?? this.smsVerified,
    );
  }
}

class OwnerSetupNotifier extends Notifier<OwnerSetupState> {
  @override
  OwnerSetupState build() => const OwnerSetupState();

  OwnerSetupService get _service => OwnerSetupService(
        companies: ref.read(companyRepositoryProvider),
        branches: ref.read(branchRepositoryProvider),
        settings: ref.read(companySettingsRepositoryProvider),
        employees: ref.read(employeeRepositoryProvider),
      );

  Future<void> loadBrandingEntitlement() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    try {
      final settings = await ref
          .read(companySettingsRepositoryProvider)
          .fetchForCompany(session.company.id);
      state = state.copyWith(
        customBrandingEnabled: settings.customBrandingEnabled,
        smsSenderId: settings.smsSenderId,
        smsSenderIdEditable: settings.smsSenderIdEditable,
        smsVerified: SmsSenderId.tryParse(settings.smsSenderId) != null,
      );
    } catch (_) {
      state = state.copyWith(customBrandingEnabled: false);
    }
  }

  void goTo(OwnerSetupStep step) {
    state = state.copyWith(step: step, clearError: true, clearInvite: true);
  }

  Future<bool> saveBusiness({
    required String businessName,
    String? phone,
    String? address,
    ProcessedMedia? logo,
  }) {
    return _run(() async {
      final session = _requireSession();
      await _service.saveBusiness(
        session: session,
        businessName: businessName,
        phone: phone,
        address: address,
        logo: logo,
      );
      if (logo != null) {
        await ref.read(brandingProvider.notifier).refresh();
      }
      state = state.copyWith(step: OwnerSetupStep.profile);
    });
  }

  Future<bool> saveProfile({required String fullName}) {
    return _run(() async {
      final session = _requireSession();
      await _service.saveOwnerProfile(session: session, fullName: fullName);
      state = state.copyWith(step: OwnerSetupStep.team);
    });
  }

  Future<bool> addSalesRep({
    required String fullName,
    required String email,
    String? phone,
  }) {
    return _run(() async {
      final session = _requireSession();
      final invite = await _service.addSalesRep(
        session: session,
        fullName: fullName,
        email: email,
        phone: phone,
      );
      state = state.copyWith(
        addedReps: [
          ...state.addedReps,
          AddedSalesRep(fullName: fullName.trim(), email: email.trim()),
        ],
        lastInvite: invite,
      );
    });
  }

  void skipTeam() {
    state = state.copyWith(step: OwnerSetupStep.sms, clearError: true);
  }

  void skipSms() {
    state = state.copyWith(step: OwnerSetupStep.ready, clearError: true);
  }

  void continueAfterSms() {
    state = state.copyWith(step: OwnerSetupStep.ready, clearError: true);
  }

  Future<bool> verifySms({
    required String senderId,
    required String phone,
  }) {
    return _run(() async {
      final sender = SmsSenderId.tryParse(senderId);
      if (sender == null) {
        throw const ValidationFailure(
          'Enter a valid Sender ID (3 to 11 letters or digits).',
        );
      }
      if (!OutboundSmsVerify.canActivateCandidate(
        storedSenderId: state.smsSenderId,
        editable: state.smsSenderIdEditable,
        candidate: sender,
      )) {
        throw const AuthorizationFailure(
          'This Sender ID is managed by Sello.',
        );
      }
      final recipient = MessagingPhone.international(phone);
      if (recipient == null) {
        throw const ValidationFailure('Enter a valid phone number.');
      }

      final result = await ref.read(outboundSmsSenderProvider).verifySender(
            recipient: recipient,
            senderId: sender,
          );
      if (!result.senderActivated) {
        throw UnexpectedFailure(OutboundSmsVerify.feedback(result));
      }
      state = state.copyWith(smsSenderId: sender, smsVerified: true);
    });
  }

  Future<bool> complete() {
    return _run(() async {
      final session = _requireSession();
      await _service.complete(session);
      await ref.read(authSessionProvider.notifier).reloadSession();
    });
  }

  Future<bool> _run(Future<void> Function() action) async {
    state = state.copyWith(isSaving: true, clearError: true, clearInvite: true);
    try {
      await action();
      state = state.copyWith(isSaving: false);
      return true;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Something went wrong. Please try again.',
      );
      return false;
    }
  }

  AppSession _requireSession() {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      throw const AuthFailure('Sign in required.');
    }
    return session;
  }
}

final ownerSetupProvider =
    NotifierProvider<OwnerSetupNotifier, OwnerSetupState>(
  OwnerSetupNotifier.new,
);
