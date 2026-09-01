import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Soft list-row hover used across dashboard and hub lists.
///
/// Instant veil fill (no fade) + optional hairline divider — matches
/// Top Customers / Action Center on the owner dashboard.
class SelloListRow extends StatefulWidget {
  const SelloListRow({
    super.key,
    required this.child,
    this.showDivider = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
  });

  final Widget child;
  final bool showDivider;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<SelloListRow> createState() => _SelloListRowState();
}

class _SelloListRowState extends State<SelloListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _hovered ? AppColors.veil : Colors.transparent,
              borderRadius: AppRadius.controlAll,
            ),
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
          if (widget.showDivider)
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.outlineSubtle,
            ),
        ],
      ),
    );

    if (widget.onTap == null) return row;
    return GestureDetector(onTap: widget.onTap, behavior: HitTestBehavior.opaque, child: row);
  }
}
