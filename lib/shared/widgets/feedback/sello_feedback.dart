import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/feedback/sello_toast.dart';

export 'package:sello/shared/widgets/feedback/sello_toast.dart';

/// Public notification API — desktop/web floating toasts, mobile bottom cards.
abstract final class SelloSnackbars {
  static SelloToastController _controller(BuildContext context) {
    final hosted = SelloToastHost.maybeOf(context);
    if (hosted != null) return hosted;
    // Fallback if a host isn't mounted yet (should be rare).
    throw FlutterError(
      'SelloSnackbars requires SelloToastHost in the widget tree. '
      'Wrap MaterialApp.builder with SelloToastHost.',
    );
  }

  static void show(
    BuildContext context, {
    required String message,
    SelloToastKind kind = SelloToastKind.info,
    String? title,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    bool showClose = true,
    Duration? duration,
  }) {
    // [icon] retained for call-site compatibility; kind drives iconography.
    _controller(context).show(
      message: message,
      kind: kind,
      title: title,
      actionLabel: actionLabel,
      onAction: onAction,
      showClose: showClose,
      duration: duration,
    );
  }

  static void success(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message: message,
      title: title,
      kind: SelloToastKind.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message: message,
      title: title,
      kind: SelloToastKind.warning,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message: message,
      title: title,
      kind: SelloToastKind.error,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message: message,
      title: title,
      kind: SelloToastKind.info,
      actionLabel: actionLabel,
      onAction: onAction,
    );
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(message),
        ),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: SelloButton(
                  label: cancelLabel,
                  variant: SelloButtonVariant.outline,
                  expanded: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SelloButton(
                  label: confirmLabel,
                  variant: destructive
                      ? SelloButtonVariant.danger
                      : SelloButtonVariant.primary,
                  expanded: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
