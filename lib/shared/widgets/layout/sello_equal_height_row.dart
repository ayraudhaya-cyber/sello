import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sello/core/responsive/responsive_layout.dart';
import 'package:sello/core/theme/theme.dart';

/// Responsive siblings that share a row when they fit, otherwise stack.
///
/// Default [equalizeHeights] matches KPI tiles: after layout, every child
/// gets [BoxConstraints.minHeight] of the tallest so the row looks even.
/// Dashboard section cards should use [SelloEqualHeightRow.natural] so each
/// card keeps its own content height (top edges still align).
///
/// Safe inside scroll views — measures after layout instead of
/// [IntrinsicHeight] / [Table], which previously blanked the Hub dashboard.
///
/// When [minChildWidth] is set and the available width cannot fit every child
/// comfortably, children stack in a column instead of being squeezed.
class SelloEqualHeightRow extends StatefulWidget {
  const SelloEqualHeightRow({
    super.key,
    required this.children,
    this.gap = AppSpacing.gap,
    this.flexes,
    this.minChildWidth,
    this.expandChildren = true,
    this.childWidth,
    this.equalizeHeights = true,
  });

  /// Same reflow as the default row, without stretching shorter cards.
  const SelloEqualHeightRow.natural({
    super.key,
    required this.children,
    this.gap = AppSpacing.gap,
    this.flexes,
    this.minChildWidth,
    this.expandChildren = true,
    this.childWidth,
  }) : equalizeHeights = false;

  final List<Widget> children;
  final double gap;

  /// Optional flex factors per child (defaults to `1` each).
  final List<int>? flexes;

  /// Stack as a column when each child would be narrower than this.
  final double? minChildWidth;

  /// When false, children keep [childWidth] instead of expanding.
  final bool expandChildren;

  /// Fixed child width when [expandChildren] is false.
  final double? childWidth;

  /// When true, shorter children stretch to the tallest. When false, each
  /// child keeps its intrinsic height and the row uses top alignment.
  final bool equalizeHeights;

  @override
  State<SelloEqualHeightRow> createState() => _SelloEqualHeightRowState();
}

class _SelloEqualHeightRowState extends State<SelloEqualHeightRow> {
  final List<GlobalKey> _keys = [];
  double? _rowHeight;

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  @override
  void didUpdateWidget(covariant SelloEqualHeightRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length ||
        oldWidget.equalizeHeights != widget.equalizeHeights) {
      _rowHeight = null;
      _syncKeys();
    }
  }

  void _syncKeys() {
    if (!widget.equalizeHeights) return;
    while (_keys.length < widget.children.length) {
      _keys.add(GlobalKey());
    }
    if (_keys.length > widget.children.length) {
      _keys.removeRange(widget.children.length, _keys.length);
    }
  }

  void _scheduleMeasure() {
    if (!widget.equalizeHeights) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    var maxH = 0.0;
    for (final key in _keys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      maxH = math.max(maxH, box.size.height);
    }
    if (maxH <= 0) return;
    // Grow when content needs more room. Fixed [SizedBox] heights previously
    // prevented growth and caused overflow; minHeight equalization can grow.
    if (_rowHeight == null || maxH > _rowHeight! + 0.5) {
      setState(() => _rowHeight = maxH);
    }
  }

  bool _shouldStack(double width) {
    final minW = widget.minChildWidth;
    if (minW == null) return false;
    return !ResponsiveLayout.canFitRow(
      width: width,
      itemCount: widget.children.length,
      minItemWidth: minW,
      gap: widget.gap,
      flexes: widget.flexes,
    );
  }

  Widget _cell(int i) {
    final child = widget.children[i];
    if (!widget.equalizeHeights) return child;
    return _EqualHeightCell(key: _keys[i], height: _rowHeight, child: child);
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.flexes == null || widget.flexes!.length == widget.children.length,
      'flexes length must match children',
    );
    assert(widget.children.isNotEmpty, 'children must not be empty');
    assert(
      widget.expandChildren || widget.childWidth != null,
      'childWidth is required when expandChildren is false',
    );

    _syncKeys();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_shouldStack(constraints.maxWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.children.length; i++) ...[
                if (i > 0) SizedBox(height: widget.gap),
                widget.children[i],
              ],
            ],
          );
        }

        _scheduleMeasure();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.children.length; i++) ...[
              if (i > 0) SizedBox(width: widget.gap),
              if (widget.expandChildren)
                Expanded(flex: widget.flexes?[i] ?? 1, child: _cell(i))
              else
                SizedBox(width: widget.childWidth, child: _cell(i)),
            ],
          ],
        );
      },
    );
  }
}

class _EqualHeightCell extends StatelessWidget {
  const _EqualHeightCell({super.key, required this.child, this.height});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (height == null) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height!),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
