import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// The signed-in person's own name and mobile number.
///
/// Shared by Hub (Settings â†’ Account) and Sello (Profile). Saves through
/// `update_my_profile`, which can touch only these two fields. The mobile
/// number matters: it is where SMS about collections and orders is sent.
class MyProfileForm extends ConsumerStatefulWidget {
  const MyProfileForm({super.key});

  @override
  ConsumerState<MyProfileForm> createState() => _MyProfileFormState();
}

class _MyProfileFormState extends ConsumerState<MyProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  String _savedName = '';
  String _savedPhone = '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final employee = ref.read(currentSessionProvider)?.employee;
    _savedName = employee?.fullName ?? '';
    _savedPhone = PhoneNumber.displayOf(employee?.phone);
    _name = TextEditingController(text: _savedName);
    _phone = TextEditingController(text: _savedPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != _savedName.trim() ||
      _phone.text.trim() != _savedPhone.trim();

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(employeeRepositoryProvider).updateMyProfile(
            fullName: _name.text,
            phone: PhoneNumber.normalizeStorage(_phone.text),
          );
      await ref.read(authSessionProvider.notifier).reloadSession();
      if (!mounted) return;
      setState(() {
        _savedName = _name.text.trim();
        _savedPhone = _phone.text.trim();
      });
      SelloSnackbars.success(context, 'Profile saved.');
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to save your profile right now.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingPhone = _savedPhone.isEmpty;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloTextField(
            controller: _name,
            label: 'Name',
            required: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Enter your name.'
                : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: _phone,
            label: 'Mobile number',
            hint: '0771234567',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            helperText: missingPhone
                ? 'Add your mobile to get SMS about collections and orders.'
                : 'Used for SMS about collections and orders.',
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s()-]')),
              LengthLimitingTextInputFormatter(20),
            ],
            validator: PhoneNumber.validator,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SelloButton(
              label: 'Save profile',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _dirty && !_saving ? _save : null,
            ),
          ),
        ],
      ),
    );
  }
}
