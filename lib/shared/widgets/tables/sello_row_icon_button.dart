import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Compact table action with a hover tooltip.
class SelloRowIconButton extends StatefulWidget {
  const SelloRowIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  /// Shows a small spinner and ignores taps while the action is starting.
  final bool loading;

  @override
  State<SelloRowIconButton> createState() => _SelloRowIconButtonState();
}

class _SelloRowIconButtonState extends State<SelloRowIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger ? AppColors.error : context.brandAccent;
    final idle = widget.danger ? AppColors.error : AppColors.textTertiary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: Duration.zero,
        child: InkWell(
          onTap: widget.loading ? null : widget.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: widget.loading
                ? SizedBox.square(
                    dimension: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  )
                : Icon(widget.icon, size: 18, color: _hovered ? accent : idle),
          ),
        ),
      ),
    );
  }
}

/// Quiet cluster of [SelloRowIconButton]s for Hub tables.
class SelloRowIconGroup extends StatelessWidget {
  const SelloRowIconGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
