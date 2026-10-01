import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';

/// Next enabled row for keyboard navigation in a Hub dropdown list.
int selloCycleEnabledIndex({
  required int current,
  required int count,
  required int delta,
  required bool Function(int index) isEnabled,
}) {
  if (count <= 0) return 0;
  var index = current;
  for (var i = 0; i < count; i++) {
    index = (index + delta) % count;
    if (index < 0) index += count;
    if (isEnabled(index)) return index;
  }
  return current.clamp(0, count - 1);
}

/// Platform-aware Sello dropdown — the default for every select control.
///
/// Desktop / web: anchored floating popup (below when possible, above otherwise).
/// Mobile: native-style bottom sheet with large touch targets.
class SelloDropdown<T> extends StatefulWidget {
  const SelloDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.label,
    this.hint,
    this.compact = false,
    this.enabled = true,
    this.required = false,
  });

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final T? value;
  final String? label;
  final String? hint;
  final bool compact;
  final bool enabled;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;

  @override
  State<SelloDropdown<T>> createState() => _SelloDropdownState<T>();
}

class _SelloDropdownState<T> extends State<SelloDropdown<T>> {
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  final _portalController = OverlayPortalController();
  late final FocusNode _focusNode;

  bool _openBelow = true;
  double _menuWidth = 200;
  double _maxMenuHeight = 280;

  static const double _gap = 6;
  static const double _menuRadius = 14;
  static const double _sheetRowHeight = 52;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'SelloDropdown');
  }

  DropdownMenuItem<T>? get _selectedItem {
    for (final item in widget.items) {
      if (item.value == widget.value) return item;
    }
    return null;
  }

  String get _displayText {
    final selected = _selectedItem;
    if (selected != null) return _labelOf(selected);
    return widget.hint ?? widget.label ?? 'Select';
  }

  bool get _showingHint => _selectedItem == null;

  String _labelOf(DropdownMenuItem<T> item) {
    final child = item.child;
    if (child is Text) return child.data ?? '';
    return item.value?.toString() ?? '';
  }

  Future<void> _handleTap() async {
    if (!widget.enabled) return;

    if (context.isMobile) {
      await _openMobileSheet();
      return;
    }

    if (_portalController.isShowing) {
      _portalController.hide();
      setState(() {});
      return;
    }

    _prepareDesktopMenuGeometry();
    _portalController.show();
    setState(() {});
  }

  void _prepareDesktopMenuGeometry() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final padding = media.padding;

    _menuWidth = size.width;

    final spaceBelow =
        screen.height - padding.bottom - (origin.dy + size.height) - _gap;
    final spaceAbove = origin.dy - padding.top - _gap;

    _openBelow = spaceBelow >= 160 || spaceBelow >= spaceAbove;
    final available = _openBelow ? spaceBelow : spaceAbove;
    _maxMenuHeight = available.clamp(120.0, 320.0);
  }

  void _select(T? value) {
    if (_portalController.isShowing) {
      _portalController.hide();
    }
    widget.onChanged(value);
    if (mounted) {
      _focusNode.requestFocus();
      setState(() {});
    }
  }

  Future<void> _openMobileSheet() async {
    final result = await showModalBottomSheet<_SheetResult<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.bottomSheetAll,
      ),
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.label ?? widget.hint ?? 'Select an option',
                      style: AppTypography.sectionTitle,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isSelected = item.value == widget.value;
                      return Material(
                        color: isSelected
                            ? context.brandAccentContainer
                            : AppColors.surfaceMuted,
                        borderRadius: AppRadius.controlAll,
                        child: InkWell(
                          borderRadius: AppRadius.controlAll,
                          onTap: item.enabled
                              ? () => Navigator.pop(
                                  context,
                                  _SheetResult<T>(item.value),
                                )
                              : null,
                          child: SizedBox(
                            height: _sheetRowHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: DefaultTextStyle(
                                      style: TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: item.enabled
                                            ? (isSelected
                                                  ? context.brandAccent
                                                  : AppColors.textPrimary)
                                            : AppColors.textFaint,
                                      ),
                                      child: item.child,
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: context.brandAccent,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) return;
    _select(result.value);
  }

  @override
  void dispose() {
    if (_portalController.isShowing) {
      _portalController.hide();
    }
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || context.isMobile) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final open = _portalController.isShowing;
    if (key == LogicalKeyboardKey.escape) {
      if (!open) return KeyEventResult.ignored;
      _portalController.hide();
      setState(() {});
      return KeyEventResult.handled;
    }
    final opensMenu =
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space;
    if (opensMenu && !open) {
      _prepareDesktopMenuGeometry();
      _portalController.show();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.compact ? _buildCompactField() : _buildFormField();

    if (context.isMobile) {
      return KeyedSubtree(
        key: _fieldKey,
        child: GestureDetector(
          onTap: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: field,
        ),
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (context) => _DesktopMenuOverlay<T>(
          link: _layerLink,
          openBelow: _openBelow,
          menuWidth: _menuWidth,
          maxMenuHeight: _maxMenuHeight,
          gap: _gap,
          menuRadius: _menuRadius,
          items: widget.items,
          value: widget.value,
          onDismiss: () {
            _portalController.hide();
            setState(() {});
            _focusNode.requestFocus();
          },
          onSelected: _select,
        ),
        child: KeyedSubtree(
          key: _fieldKey,
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _onFieldKey,
            child: GestureDetector(
              onTap: () {
                _focusNode.requestFocus();
                _handleTap();
              },
              behavior: HitTestBehavior.opaque,
              child: field,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactField() {
    final open = !context.isMobile && _portalController.isShowing;
    final focused = _focusNode.hasFocus || open;
    final field = SizedBox(
      height: AppSpacing.controlHeight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.inputAll,
          border: Border.all(
            color: focused ? context.brandAccent : AppColors.outline,
            width: focused ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  color: _showingHint
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(
              open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );

    final labelText = widget.label?.trim();
    if (labelText == null || labelText.isEmpty) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          labelText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        field,
      ],
    );
  }

  Widget _buildFormField() {
    final open = !context.isMobile && _portalController.isShowing;
    final focused = _focusNode.hasFocus || open;
    return InputDecorator(
      isFocused: focused,
      isEmpty: _showingHint,
      decoration: InputDecoration(
        label: SelloFieldLabel.decorationLabel(
          widget.label,
          required: widget.required,
        ),
        hintText: widget.hint,
        enabled: widget.enabled,
        suffixIcon: Icon(
          open
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 20,
          color: AppColors.textTertiary,
        ),
      ),
      child: Text(
        _showingHint ? '' : _displayText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodyMedium?.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

class _SheetResult<T> {
  const _SheetResult(this.value);
  final T? value;
}

class _DesktopMenuOverlay<T> extends StatefulWidget {
  const _DesktopMenuOverlay({
    required this.link,
    required this.openBelow,
    required this.menuWidth,
    required this.maxMenuHeight,
    required this.gap,
    required this.menuRadius,
    required this.items,
    required this.value,
    required this.onDismiss,
    required this.onSelected,
  });

  final LayerLink link;
  final bool openBelow;
  final double menuWidth;
  final double maxMenuHeight;
  final double gap;
  final double menuRadius;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  final VoidCallback onDismiss;
  final ValueChanged<T?> onSelected;

  @override
  State<_DesktopMenuOverlay<T>> createState() => _DesktopMenuOverlayState<T>();
}

class _DesktopMenuOverlayState<T> extends State<_DesktopMenuOverlay<T>> {
  /// Keyboard / hover highlight — only one row at a time.
  late int _activeIndex;
  final _scroll = ScrollController();
  final _menuFocus = FocusNode();
  static const _rowHeight = 44.0;

  @override
  void initState() {
    super.initState();
    final selected = widget.items.indexWhere(
      (item) => item.value == widget.value,
    );
    _activeIndex = selected >= 0 ? selected : 0;
    _activeIndex = selloCycleEnabledIndex(
      current: _activeIndex - 1,
      count: widget.items.length,
      delta: 1,
      isEnabled: (index) => widget.items[index].enabled,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _menuFocus.dispose();
    super.dispose();
  }

  void _setActive(int index) {
    if (_activeIndex == index) return;
    setState(() => _activeIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (index * _rowHeight).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
    });
  }

  void _move(int delta) {
    _setActive(
      selloCycleEnabledIndex(
        current: _activeIndex,
        count: widget.items.length,
        delta: delta,
        isEnabled: (index) => widget.items[index].enabled,
      ),
    );
  }

  void _selectActive() {
    if (_activeIndex < 0 || _activeIndex >= widget.items.length) return;
    final item = widget.items[_activeIndex];
    if (!item.enabled) return;
    widget.onSelected(item.value);
  }

  KeyEventResult _onMenuKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _selectActive();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          targetAnchor: widget.openBelow
              ? Alignment.bottomLeft
              : Alignment.topLeft,
          followerAnchor: widget.openBelow
              ? Alignment.topLeft
              : Alignment.bottomLeft,
          offset: Offset(0, widget.openBelow ? widget.gap : -widget.gap),
          child: Material(
            color: AppColors.surface,
            elevation: 0,
            shadowColor: Colors.transparent,
            borderRadius: BorderRadius.circular(widget.menuRadius),
            clipBehavior: Clip.antiAlias,
            child: Focus(
              focusNode: _menuFocus,
              autofocus: true,
              onKeyEvent: _onMenuKey,
              child: MouseRegion(
                onExit: (_) {},
                child: Container(
                  width: widget.menuWidth,
                  constraints: BoxConstraints(maxHeight: widget.maxMenuHeight),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(widget.menuRadius),
                    border: Border.all(color: AppColors.outlinePanel),
                    boxShadow: AppShadows.level2,
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isSelected = item.value == widget.value;
                      final isHovered = _activeIndex == index;
                      return _DesktopMenuRow<T>(
                        item: item,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        onHover: item.enabled ? () => _setActive(index) : null,
                        onSelected: widget.onSelected,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopMenuRow<T> extends StatelessWidget {
  const _DesktopMenuRow({
    required this.item,
    required this.isSelected,
    required this.isHovered,
    required this.onSelected,
    this.onHover,
  });

  final DropdownMenuItem<T> item;
  final bool isSelected;
  final bool isHovered;
  final ValueChanged<T?> onSelected;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final enabled = item.enabled;

    final Color background;
    if (!enabled) {
      background = Colors.transparent;
    } else if (isSelected && isHovered) {
      background = context.brandAccentContainer;
    } else if (isSelected) {
      background = context.brandAccentContainer.withValues(alpha: 0.65);
    } else if (isHovered) {
      background = AppColors.veil;
    } else {
      background = Colors.transparent;
    }

    final emphasize = enabled && (isSelected || isHovered);

    return MouseRegion(
      // Enter only — parent clears hover when the pointer leaves the menu.
      // Never rely on per-row onExit (unreliable between adjacent rows on web).
      onEnter: onHover == null ? null : (_) => onHover!(),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onSelected(item.value) : null,
        child: ColoredBox(
          color: background,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        fontWeight: emphasize
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: !enabled
                            ? AppColors.textFaint
                            : (emphasize
                                  ? context.brandAccent
                                  : AppColors.textPrimary),
                      ),
                      child: item.child,
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: context.brandAccent,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
