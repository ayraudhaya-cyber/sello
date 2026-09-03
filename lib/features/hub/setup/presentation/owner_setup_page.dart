import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/features/hub/setup/application/owner_setup_provider.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/services/onboarding/onboarding_validation.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// First-time Owner setup after the company already exists.
class OwnerSetupPage extends ConsumerStatefulWidget {
  const OwnerSetupPage({super.key});

  @override
  ConsumerState<OwnerSetupPage> createState() => _OwnerSetupPageState();
}

class _OwnerSetupPageState extends ConsumerState<OwnerSetupPage> {
  final _businessFormKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();
  final _teamFormKey = GlobalKey<FormState>();

  late final TextEditingController _businessName;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _fullName;
  late final TextEditingController _email;
  final _repName = TextEditingController();
  final _repEmail = TextEditingController();
  final _repPhone = TextEditingController();
  final _smsSenderId = TextEditingController();
  final _smsTestPhone = TextEditingController();

  final _media = MediaService();
  ProcessedMedia? _pendingLogo;
  bool _pickingLogo = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(currentSessionProvider);
    _businessName = TextEditingController(text: session?.company.name ?? '');
    _phone = TextEditingController(
      text: PhoneNumber.displayOf(session?.branch?.phone),
    );
    _address = TextEditingController(text: session?.branch?.addressLine1 ?? '');
    _fullName = TextEditingController(text: session?.employee.fullName ?? '');
    _email = TextEditingController(text: session?.email ?? '');
    Future.microtask(
      () => ref.read(ownerSetupProvider.notifier).loadBrandingEntitlement(),
    );
  }

  @override
  void dispose() {
    _businessName.dispose();
    _phone.dispose();
    _address.dispose();
    _fullName.dispose();
    _email.dispose();
    _repName.dispose();
    _repEmail.dispose();
    _repPhone.dispose();
    _smsSenderId.dispose();
    _smsTestPhone.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    setState(() => _pickingLogo = true);
    try {
      final file = await _media.pickWithBestExperience(context);
      if (file == null || !mounted) return;
      final raw = await file.readAsBytes();
      if (!mounted) return;
      final prepared = await _media.prepareForUpload(context, raw);
      if (prepared == null || !mounted) return;
      setState(() => _pendingLogo = prepared);
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  Future<void> _submitBusiness() async {
    if (!(_businessFormKey.currentState?.validate() ?? false)) return;
    await ref.read(ownerSetupProvider.notifier).saveBusiness(
          businessName: _businessName.text,
          phone: _phone.text,
          address: _address.text,
          logo: _pendingLogo,
        );
  }

  Future<void> _submitProfile() async {
    if (!(_profileFormKey.currentState?.validate() ?? false)) return;
    await ref.read(ownerSetupProvider.notifier).saveProfile(
          fullName: _fullName.text,
        );
  }

  Future<void> _addRep() async {
    if (!(_teamFormKey.currentState?.validate() ?? false)) return;
    final ok = await ref.read(ownerSetupProvider.notifier).addSalesRep(
          fullName: _repName.text,
          email: _repEmail.text,
          phone: _repPhone.text,
        );
    if (!ok || !mounted) return;
    _repName.clear();
    _repEmail.clear();
    _repPhone.clear();
    final invite = ref.read(ownerSetupProvider).lastInvite;
    if (invite == null) return;
    if (invite.emailDelivered) {
      SelloSnackbars.success(context, 'Invitation email sent.');
    } else if (invite.emailUnavailable) {
      SelloSnackbars.info(
        context,
        'Sales Rep added, but the invitation email could not be sent.',
      );
    } else {
      SelloSnackbars.success(context, 'Sales Rep added.');
    }
  }

  Future<void> _testSms() async {
    await ref.read(ownerSetupProvider.notifier).verifySms(
          senderId: _smsSenderId.text,
          phone: _smsTestPhone.text,
        );
  }

  Future<void> _finish() async {
    final ok = await ref.read(ownerSetupProvider.notifier).complete();
    if (!ok || !mounted) return;
    context.go(RoutePaths.hubDashboard);
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(ownerSetupProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.canvas),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppGradients.heroWash),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: Column(
                      children: [
                        const SelloBrandMark(size: 28),
                        const SizedBox(height: 28),
                        if (setup.step != OwnerSetupStep.welcome &&
                            setup.step != OwnerSetupStep.ready)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _stepLabel(setup.step),
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: _body(setup),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stepLabel(OwnerSetupStep step) {
    return switch (step) {
      OwnerSetupStep.business => 'Step 2 of 6',
      OwnerSetupStep.profile => 'Step 3 of 6',
      OwnerSetupStep.team => 'Step 4 of 6',
      OwnerSetupStep.sms => 'Step 5 of 6',
      _ => '',
    };
  }

  Widget _body(OwnerSetupState setup) {
    return switch (setup.step) {
      OwnerSetupStep.welcome => _WelcomeStep(
          onStart: () =>
              ref.read(ownerSetupProvider.notifier).goTo(OwnerSetupStep.business),
        ),
      OwnerSetupStep.business => _BusinessStep(
          formKey: _businessFormKey,
          nameController: _businessName,
          phoneController: _phone,
          addressController: _address,
          showLogo: setup.customBrandingEnabled,
          pickingLogo: _pickingLogo,
          hasLogo: _pendingLogo != null,
          onPickLogo: _pickLogo,
          saving: setup.isSaving,
          error: setup.errorMessage,
          onContinue: _submitBusiness,
        ),
      OwnerSetupStep.profile => _ProfileStep(
          formKey: _profileFormKey,
          nameController: _fullName,
          emailController: _email,
          saving: setup.isSaving,
          error: setup.errorMessage,
          onBack: () =>
              ref.read(ownerSetupProvider.notifier).goTo(OwnerSetupStep.business),
          onContinue: _submitProfile,
        ),
      OwnerSetupStep.team => _TeamStep(
          formKey: _teamFormKey,
          nameController: _repName,
          emailController: _repEmail,
          phoneController: _repPhone,
          added: setup.addedReps,
          saving: setup.isSaving,
          error: setup.errorMessage,
          onAdd: _addRep,
          onSkip: () => ref.read(ownerSetupProvider.notifier).skipTeam(),
          onContinue: () =>
              ref.read(ownerSetupProvider.notifier).skipTeam(),
        ),
      OwnerSetupStep.sms => _SmsStep(
          senderIdController: _smsSenderId,
          phoneController: _smsTestPhone,
          ready: setup.smsReady,
          configuredSenderId: setup.smsSenderId,
          saving: setup.isSaving,
          error: setup.errorMessage,
          onTest: _testSms,
          onSkip: () => ref.read(ownerSetupProvider.notifier).skipSms(),
          onContinue: () =>
              ref.read(ownerSetupProvider.notifier).continueAfterSms(),
          onBack: () =>
              ref.read(ownerSetupProvider.notifier).goTo(OwnerSetupStep.team),
        ),
      OwnerSetupStep.ready => _ReadyStep(
          saving: setup.isSaving,
          error: setup.errorMessage,
          onFinish: _finish,
        ),
    };
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Text(
          'Let’s get your business set up.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.25,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'A few details now will make Sello feel like yours. This only takes a couple of minutes.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 15,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 36),
        SelloButton(
          label: 'Get started',
          onPressed: onStart,
          expanded: true,
        ),
      ],
    );
  }
}

class _BusinessStep extends StatelessWidget {
  const _BusinessStep({
    required this.formKey,
    required this.nameController,
    required this.phoneController,
    required this.addressController,
    required this.showLogo,
    required this.pickingLogo,
    required this.hasLogo,
    required this.onPickLogo,
    required this.saving,
    required this.error,
    required this.onContinue,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final bool showLogo;
  final bool pickingLogo;
  final bool hasLogo;
  final VoidCallback onPickLogo;
  final bool saving;
  final String? error;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SettingsGroupCard(
        title: 'Business details',
        description: 'Confirm how your company appears in Sello.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsCompactField(
              label: 'Business name',
              required: true,
              child: SelloTextField(
                controller: nameController,
                hint: 'Unitech Traders',
                textInputAction: TextInputAction.next,
                validator: OnboardingValidation.businessName,
              ),
            ),
            const SizedBox(height: 16),
            SettingsTwoUp(
              children: [
                SettingsCompactField(
                  label: 'Business phone',
                  child: SelloTextField(
                    controller: phoneController,
                    hint: '+94 77 123 4567',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: OnboardingValidation.ownerPhone,
                  ),
                ),
                SettingsCompactField(
                  label: 'Address',
                  child: SelloTextField(
                    controller: addressController,
                    hint: 'Street, city',
                    textInputAction: TextInputAction.done,
                  ),
                ),
              ],
            ),
            if (showLogo) ...[
              const SizedBox(height: 16),
              SettingsCompactField(
                label: 'Logo',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelloButton(
                    label: pickingLogo
                        ? 'Preparing…'
                        : hasLogo
                            ? 'Logo selected'
                            : 'Add logo',
                    variant: SelloButtonVariant.outline,
                    size: SelloButtonSize.small,
                    icon: Icons.image_outlined,
                    onPressed: pickingLogo ? null : onPickLogo,
                  ),
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SelloButton(
              label: 'Continue',
              onPressed: saving ? null : onContinue,
              loading: saving,
              expanded: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.saving,
    required this.error,
    required this.onBack,
    required this.onContinue,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final bool saving;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SettingsGroupCard(
        title: 'Your profile',
        description: 'This is how your team will see you in Sello.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsCompactField(
              label: 'Full name',
              required: true,
              child: SelloTextField(
                controller: nameController,
                hint: 'Your name',
                textInputAction: TextInputAction.done,
                validator: OnboardingValidation.ownerFullName,
              ),
            ),
            const SizedBox(height: 16),
            SettingsCompactField(
              label: 'Email',
              helper: 'From your Sello account',
              child: SelloTextField(
                controller: emailController,
                enabled: false,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SelloButton(
              label: 'Continue',
              onPressed: saving ? null : onContinue,
              loading: saving,
              expanded: true,
            ),
            const SizedBox(height: 10),
            SelloButton(
              label: 'Back',
              variant: SelloButtonVariant.ghost,
              onPressed: saving ? null : onBack,
              expanded: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamStep extends StatelessWidget {
  const _TeamStep({
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.added,
    required this.saving,
    required this.error,
    required this.onAdd,
    required this.onSkip,
    required this.onContinue,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final List<AddedSalesRep> added;
  final bool saving;
  final String? error;
  final VoidCallback onAdd;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SettingsGroupCard(
        title: 'Add your sales team',
        description: 'Invite Sales Reps now, or skip and add them later from Team.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (added.isNotEmpty) ...[
              for (final rep in added)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${rep.fullName}  ·  ${rep.email}',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
            SettingsCompactField(
              label: 'Full name',
              required: true,
              child: SelloTextField(
                controller: nameController,
                hint: 'Sales rep name',
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if ((value ?? '').trim().isEmpty &&
                      emailController.text.trim().isEmpty) {
                    return null;
                  }
                  return OnboardingValidation.ownerFullName(value);
                },
              ),
            ),
            const SizedBox(height: 16),
            SettingsTwoUp(
              children: [
                SettingsCompactField(
                  label: 'Email',
                  required: true,
                  child: SelloTextField(
                    controller: emailController,
                    hint: 'name@company.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty &&
                          nameController.text.trim().isEmpty) {
                        return null;
                      }
                      return OnboardingValidation.ownerEmail(value);
                    },
                  ),
                ),
                SettingsCompactField(
                  label: 'Phone',
                  child: SelloTextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    validator: OnboardingValidation.ownerPhone,
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SelloButton(
              label: 'Add Sales Rep',
              icon: Icons.add,
              variant: SelloButtonVariant.outline,
              onPressed: saving ? null : onAdd,
              loading: saving,
              expanded: true,
            ),
            const SizedBox(height: 10),
            SelloButton(
              label: added.isEmpty ? 'Skip for now' : 'Continue',
              onPressed: saving ? null : (added.isEmpty ? onSkip : onContinue),
              expanded: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SmsStep extends StatefulWidget {
  const _SmsStep({
    required this.senderIdController,
    required this.phoneController,
    required this.ready,
    required this.configuredSenderId,
    required this.saving,
    required this.error,
    required this.onTest,
    required this.onSkip,
    required this.onContinue,
    required this.onBack,
  });

  final TextEditingController senderIdController;
  final TextEditingController phoneController;
  final bool ready;
  final String? configuredSenderId;
  final bool saving;
  final String? error;
  final VoidCallback onTest;
  final VoidCallback onSkip;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  State<_SmsStep> createState() => _SmsStepState();
}

class _SmsStepState extends State<_SmsStep> {
  @override
  Widget build(BuildContext context) {
    if (widget.ready) {
      return SettingsGroupCard(
        title: OutboundSmsVerify.successTitle,
        description: OutboundSmsVerify.successBody,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (SmsSenderId.tryParse(widget.configuredSenderId) != null)
              Text(
                'Sender ID: ${widget.configuredSenderId}',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 24),
            SelloButton(
              label: 'Continue',
              onPressed: widget.saving ? null : widget.onContinue,
              expanded: true,
            ),
            const SizedBox(height: 10),
            SelloButton(
              label: 'Back',
              variant: SelloButtonVariant.ghost,
              onPressed: widget.saving ? null : widget.onBack,
              expanded: true,
            ),
          ],
        ),
      );
    }

    final senderValid =
        SmsSenderId.tryParse(widget.senderIdController.text) != null;
    final phoneValid =
        MessagingPhone.international(widget.phoneController.text) != null;
    final canTest = senderValid && phoneValid && !widget.saving;

    return SettingsGroupCard(
      title: OutboundSmsVerify.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.infoContainer,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Text(
              OutboundSmsVerify.explanation,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                height: 1.45,
                color: AppColors.info,
              ),
            ),
          ),
          const SizedBox(height: 18),
          SettingsCompactField(
            label: 'SMS Sender ID',
            child: SelloTextField(
              controller: widget.senderIdController,
              hint: 'Enter your Sender ID',
              textInputAction: TextInputAction.next,
              enabled: !widget.saving,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(SmsSenderId.maxLength),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (senderValid) ...[
            const SizedBox(height: 16),
            SettingsCompactField(
              label: 'Test phone number',
              helper: 'We send a real test SMS to this number.',
              child: SelloTextField(
                controller: widget.phoneController,
                hint: '076 564 4465',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                enabled: !widget.saving,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
          if (widget.error != null) ...[
            const SizedBox(height: 16),
            Text(
              widget.error!,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (senderValid)
            SelloButton(
              label: 'Test SMS',
              onPressed: canTest ? widget.onTest : null,
              loading: widget.saving,
              expanded: true,
            ),
          if (senderValid) const SizedBox(height: 10),
          SelloButton(
            label: 'Skip for now',
            variant: senderValid
                ? SelloButtonVariant.outline
                : SelloButtonVariant.primary,
            onPressed: widget.saving ? null : widget.onSkip,
            expanded: true,
          ),
          const SizedBox(height: 10),
          SelloButton(
            label: 'Back',
            variant: SelloButtonVariant.ghost,
            onPressed: widget.saving ? null : widget.onBack,
            expanded: true,
          ),
        ],
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({
    required this.saving,
    required this.error,
    required this.onFinish,
  });

  final bool saving;
  final String? error;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Text(
          'You’re all set.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.25,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your Sello workspace is ready.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 15,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.error,
            ),
          ),
        ],
        const SizedBox(height: 36),
        SelloButton(
          label: 'Go to Sello',
          onPressed: saving ? null : onFinish,
          loading: saving,
          expanded: true,
        ),
      ],
    );
  }
}
