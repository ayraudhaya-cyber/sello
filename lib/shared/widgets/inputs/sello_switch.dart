import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/theme/theme.dart';

/// Calm pill switch with smooth thumb travel — Sello forms and settings.
class SelloSwitch extends StatelessWidget {
  const SelloSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  static const double width = 46;
  static const double height = 26;
  static const double thumbSize = 20;
  static const double padding = 3;

  bool get _interactive => enabled && onChanged != null;

  @override
  Widget build(BuildContext context) {
    final accent = context.brandAccent;

    return Semantics(
      button: true,
      toggled: value,
      enabled: _interactive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _interactive
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: AnimatedOpacity(
          duration: AppDurations.fast,
          curve: AppCurves.standard,
          opacity: _interactive ? 1 : 0.55,
          child: AnimatedContainer(
            duration: AppDurations.normal,
            curve: AppCurves.emphasized,
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: value ? accent : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: value
                    ? accent.withValues(alpha: 0.4)
                    : AppColors.outlinePanel,
              ),
            ),
            child: AnimatedAlign(
              duration: AppDurations.normal,
              curve: AppCurves.emphasized,
              alignment:
                  value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(padding),
                child: AnimatedContainer(
                  duration: AppDurations.normal,
                  curve: AppCurves.emphasized,
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: value ? AppColors.onPrimary : AppColors.surface,
                    borderRadius: BorderRadius.circular(thumbSize / 2),
                    boxShadow: [
                      BoxShadow(
                        color: value
                            ? accent.withValues(alpha: 0.32)
                            : Colors.black.withValues(alpha: 0.1),
                        blurRadius: value ? 5 : 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
