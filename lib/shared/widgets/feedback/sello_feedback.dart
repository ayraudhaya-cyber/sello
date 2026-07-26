import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';

abstract final class SelloSnackbars {
  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.surface),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  static void success(BuildContext context, String message) {
    show(context, message: message, icon: Icons.check_circle_rounded);
  }

  static void error(BuildContext context, String message) {
    show(context, message: message, icon: Icons.error_outline_rounded);
  }
}

Future<bool?> showSelloDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        actions: [
          SelloButton(
            label: cancelLabel,
            variant: SelloButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SelloButton(
            label: confirmLabel,
            variant: destructive
                ? SelloButtonVariant.primary
                : SelloButtonVariant.gradient,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
}
