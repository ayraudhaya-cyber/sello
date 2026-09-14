import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/dialogs/sello_form_dialog.dart';
import 'package:sello/shared/widgets/feedback/sello_feedback.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

/// Opens the shared Change password dialog. Returns `true` when updated.
Future<bool> showChangePasswordDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const ChangePasswordDialog(),
  );
  if (result == true && context.mounted) {
    SelloSnackbars.success(context, 'Password updated.');
  }
  return result == true;
}

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  var _obscureCurrent = true;
  var _obscureNew = true;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await ref.read(authServiceProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to update password. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Change password',
      subtitle:
          'Update the password you use to sign in. Your email and profile '
          'details stay the same — ask an Owner or Manager to change those.',
      maxWidth: 480,
      formKey: _formKey,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: context.texts.bodySmall?.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SelloTextField(
            controller: _currentController,
            label: 'Current password',
            required: true,
            obscureText: _obscureCurrent,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.lock_outline_rounded,
            enabled: !_saving,
            autofillHints: const [AutofillHints.password],
            suffixIcon: _visibilityToggle(
              obscure: _obscureCurrent,
              enabled: !_saving,
              onPressed: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Current password is required';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: _newController,
            label: 'New password',
            required: true,
            obscureText: _obscureNew,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.lock_outline_rounded,
            enabled: !_saving,
            autofillHints: const [AutofillHints.newPassword],
            suffixIcon: _visibilityToggle(
              obscure: _obscureNew,
              enabled: !_saving,
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'New password is required';
              }
              if (value.length < 8) {
                return 'Password must be at least 8 characters';
              }
              if (value == _currentController.text) {
                return 'New password must be different';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: _confirmController,
            label: 'Confirm new password',
            required: true,
            obscureText: _obscureNew,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: _saving ? null : (_) => _submit(),
            prefixIcon: Icons.lock_reset_rounded,
            enabled: !_saving,
            autofillHints: const [AutofillHints.newPassword],
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your new password';
              }
              if (value != _newController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
        ],
      ),
      footer: SelloDialogFooter(
        primaryLabel: 'Update password',
        primaryLoading: _saving,
        primaryEnabled: !_saving,
        onPrimary: _saving ? null : _submit,
        onCancel: _saving ? null : () => Navigator.of(context).maybePop(false),
      ),
    );
  }

  Widget _visibilityToggle({
    required bool obscure,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return ExcludeFocus(
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        tooltip: obscure ? 'Show password' : 'Hide password',
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    );
  }
}
