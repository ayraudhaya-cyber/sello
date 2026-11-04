import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:sello/core/responsive/responsive_layout.dart';
import 'package:sello/core/theme/theme.dart';

/// Responsive siblings that share a row when they fit, otherwise stack.
///
/// Default [equalizeHeights] matches KPI tiles: after layout, every child
/// gets the height of the tallest so the row looks even.
/// [tightHeights] stretches the shorter card to the shared height. The
/// shared height is a minimum: a list that loads after the first frame
/// still grows the row instead of overflowing a locked slot.
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
    this.tightHeights = false,
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
    this.tightHeights = false,
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

  /// Stretch shorter cards up to the tallest sibling.
  ///
  /// The shared height is a floor. Dashboard pairs use this so surfaces
  /// line up, while a list that arrives later can still grow the row.
  final bool tightHeights;

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
    // Only grow. The cell height is already max(content, slot), so a later
    // list still reports a taller box. Shrinking here fights the stretch
    // and retriggers layout every frame.
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
    return _EqualHeightCell(
      key: _keys[i],
      minHeight: _rowHeight,
      tight: widget.tightHeights,
      child: child,
    );
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

/// At least [minHeight], and taller when the child needs it.
///
/// [tight] gives a shorter card the shared height as a real max so its
/// chart or surface can fill the row. Content that is taller than the slot
/// is laid out unbounded, so a list that arrives later still grows the row.
class _EqualHeightCell extends SingleChildRenderObjectWidget {
  const _EqualHeightCell({
    super.key,
    required super.child,
    required this.minHeight,
    required this.tight,
  });

  final double? minHeight;
  final bool tight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEqualHeightCell(minHeight: minHeight, tight: tight);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightCell renderObject,
  ) {
    renderObject
      ..minHeight = minHeight
      ..tight = tight;
  }
}

class _RenderEqualHeightCell extends RenderProxyBox {
  _RenderEqualHeightCell({required double? minHeight, required bool tight})
    : _minHeight = minHeight,
      _tight = tight;

  double? _minHeight;
  bool _tight;

  double? get minHeight => _minHeight;
  set minHeight(double? value) {
    if (_minHeight == value) return;
    _minHeight = value;
    markNeedsLayout();
  }

  bool get tight => _tight;
  set tight(bool value) {
    if (_tight == value) return;
    _tight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }

    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.minWidth;
    child.layout(
      BoxConstraints(minWidth: width, maxWidth: width),
      parentUsesSize: true,
    );
    final natural = child.size.height;
    final slot = _minHeight;
    final height = slot == null ? natural : math.max(natural, slot);
    // Stretch a shorter card up to the row, but never cap it. A tight max
    // froze the first measurement and painted overflow on lists that grew.
    if (slot != null && height > natural + 0.5) {
      child.layout(
        BoxConstraints(minWidth: width, maxWidth: width, minHeight: height),
        parentUsesSize: true,
      );
    }
    size = constraints.constrain(
      Size(width, math.max(height, child.size.height)),
    );
  }
}
