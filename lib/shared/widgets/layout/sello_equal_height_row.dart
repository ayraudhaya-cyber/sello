import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sello/core/theme/theme.dart';

/// Sello standard: siblings in a row share one height (tallest wins).
///
/// Safe inside scroll views — measures after layout instead of [IntrinsicHeight]
/// / [Table], which previously blanked the Hub dashboard.
class SelloEqualHeightRow extends StatefulWidget {
  const SelloEqualHeightRow({
    super.key,
    required this.children,
    this.gap = AppSpacing.gap,
    this.flexes,
  });

  final List<Widget> children;
  final double gap;

  /// Optional flex factors per child (defaults to `1` each).
  final List<int>? flexes;

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
    if (oldWidget.children.length != widget.children.length) {
      _rowHeight = null;
      _syncKeys();
    }
  }

  void _syncKeys() {
    while (_keys.length < widget.children.length) {
      _keys.add(GlobalKey());
    }
    if (_keys.length > widget.children.length) {
      _keys.removeRange(widget.children.length, _keys.length);
    }
  }

  void _scheduleMeasure() {
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
    if (_rowHeight == null || (_rowHeight! - maxH).abs() > 0.5) {
      setState(() => _rowHeight = maxH);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.flexes == null ||
          widget.flexes!.length == widget.children.length,
      'flexes length must match children',
    );
    assert(widget.children.isNotEmpty, 'children must not be empty');

    _syncKeys();
    _scheduleMeasure();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.children.length; i++) ...[
          if (i > 0) SizedBox(width: widget.gap),
          Expanded(
            flex: widget.flexes?[i] ?? 1,
            child: _EqualHeightCell(
              key: _keys[i],
              height: _rowHeight,
              child: widget.children[i],
            ),
          ),
        ],
      ],
    );
  }
}

class _EqualHeightCell extends StatelessWidget {
  const _EqualHeightCell({
    super.key,
    required this.child,
    this.height,
  });

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (height == null) return child;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: child,
    );
  }
}
