import 'package:flutter/material.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';

enum SelloToastKind { success, warning, error, info }

/// Root host that renders floating toasts above the app (including dialogs).
///
/// Wrap the [MaterialApp] builder child with this widget once.
///
/// Layout lives above the navigator Overlay — never use [Tooltip] /
/// [IconButton.tooltip] inside toast cards.
class SelloToastHost extends StatefulWidget {
  const SelloToastHost({super.key, required this.child});

  final Widget child;

  static SelloToastController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SelloToastScope>();
    assert(scope != null, 'SelloToastHost is missing above this context.');
    return scope!.controller;
  }

  static SelloToastController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SelloToastScope>()
        ?.controller;
  }

  @override
  State<SelloToastHost> createState() => _SelloToastHostState();
}

class SelloToastController {
  SelloToastController._(this._state);

  final _SelloToastHostState _state;

  void show({
    required String message,
    SelloToastKind kind = SelloToastKind.info,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    bool showClose = true,
    Duration? duration,
  }) {
    _state._show(
      message: message,
      kind: kind,
      title: title,
      actionLabel: actionLabel,
      onAction: onAction,
      showClose: showClose,
      duration: duration,
    );
  }

  void dismiss(String id) => _state._dismiss(id);

  void dismissAll() => _state._dismissAll();
}

class _SelloToastScope extends InheritedWidget {
  const _SelloToastScope({
    required this.controller,
    required super.child,
  });

  final SelloToastController controller;

  @override
  bool updateShouldNotify(covariant _SelloToastScope oldWidget) =>
      controller != oldWidget.controller;
}

class _ToastData {
  _ToastData({
    required this.id,
    required this.kind,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
    this.showClose = true,
    required this.duration,
  });

  final String id;
  final SelloToastKind kind;
  final String message;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showClose;
  final Duration duration;
}

class _SelloToastHostState extends State<SelloToastHost> {
  late final SelloToastController _controller = SelloToastController._(this);
  final List<_ToastData> _toasts = [];
  int _seq = 0;

  static const int _maxVisible = 3;
  static const double _desktopWidth = 400;

  void _show({
    required String message,
    required SelloToastKind kind,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    bool showClose = true,
    Duration? duration,
  }) {
    final id = 'toast_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final entry = _ToastData(
      id: id,
      kind: kind,
      message: message,
      title: title,
      actionLabel: actionLabel,
      onAction: onAction,
      showClose: showClose,
      duration: duration ?? _defaultDuration(kind),
    );

    setState(() {
      _toasts.insert(0, entry);
      while (_toasts.length > _maxVisible) {
        _toasts.removeLast();
      }
    });
  }

  Duration _defaultDuration(SelloToastKind kind) {
    return switch (kind) {
      SelloToastKind.success => const Duration(milliseconds: 2800),
      SelloToastKind.warning => const Duration(seconds: 4),
      SelloToastKind.info => const Duration(milliseconds: 3500),
      SelloToastKind.error => Duration.zero,
    };
  }

  void _dismiss(String id) {
    if (!_toasts.any((t) => t.id == id)) return;
    setState(() => _toasts.removeWhere((t) => t.id == id));
  }

  void _dismissAll() {
    setState(() => _toasts.clear());
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;

    return _SelloToastScope(
      controller: _controller,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_toasts.isNotEmpty)
            Align(
              alignment:
                  isMobile ? Alignment.bottomCenter : Alignment.topRight,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 20,
                    isMobile ? 0 : 16,
                    isMobile ? 16 : 20,
                    isMobile ? 16 : 0,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: isMobile ? 0 : 360,
                      maxWidth: isMobile ? double.infinity : _desktopWidth,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final toast in _toasts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SelloToastCard(
                              key: ValueKey(toast.id),
                              data: toast,
                              fromTop: !isMobile,
                              onClose: () => _dismiss(toast.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelloToastCard extends StatefulWidget {
  const _SelloToastCard({
    super.key,
    required this.data,
    required this.fromTop,
    required this.onClose,
  });

  final _ToastData data;
  final bool fromTop;
  final VoidCallback onClose;

  @override
  State<_SelloToastCard> createState() => _SelloToastCardState();
}

class _SelloToastCardState extends State<_SelloToastCard>
    with TickerProviderStateMixin {
  static const Duration _motion = Duration(milliseconds: 200);

  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: _motion,
  );
  late final AnimationController? _progressController;

  late final Animation<double> _fade = CurvedAnimation(
    parent: _motionController,
    curve: AppCurves.standard,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.98, end: 1).animate(
    CurvedAnimation(
      parent: _motionController,
      curve: AppCurves.standard,
      reverseCurve: Curves.easeInCubic,
    ),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.fromTop ? const Offset(0, -0.12) : const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _motionController,
      curve: AppCurves.standard,
      reverseCurve: Curves.easeInCubic,
    ),
  );

  bool _closing = false;

  bool get _hasAutoDismiss => widget.data.duration > Duration.zero;

  @override
  void initState() {
    super.initState();
    if (_hasAutoDismiss) {
      _progressController = AnimationController(
        vsync: this,
        duration: widget.data.duration,
      )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _close();
        });
      _progressController!.forward();
    } else {
      _progressController = null;
    }
    _motionController.forward();
  }

  @override
  void dispose() {
    _progressController?.dispose();
    _motionController.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _progressController?.stop();
    await _motionController.reverse();
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = _paletteFor(data.kind);
    final hasAction =
        data.actionLabel != null && data.actionLabel!.trim().isNotEmpty;
    final hasTitle = data.title != null && data.title!.trim().isNotEmpty;
    final radius = BorderRadius.circular(AppRadius.panel);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: radius,
                border: Border.all(color: AppColors.outlinePanel),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2C1D7A).withValues(alpha: 0.07),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: const Color(0xFF2C1D7A).withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        16,
                        data.showClose ? 12 : 18,
                        hasAction ? 12 : 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: hasTitle || hasAction
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.center,
                            children: [
                              _ToastIcon(palette: palette),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _MessageBlock(
                                  title: hasTitle ? data.title : null,
                                  message: data.message,
                                ),
                              ),
                              if (data.showClose) ...[
                                const SizedBox(width: 8),
                                _ToastCloseButton(onTap: _close),
                              ],
                            ],
                          ),
                          if (hasAction) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  data.onAction?.call();
                                  _close();
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: context.brandAccent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: Text(data.actionLabel!),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_progressController case final progress?)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedBuilder(
                          animation: progress,
                          builder: (context, child) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor:
                                    (1 - progress.value).clamp(0.0, 1.0),
                                child: child,
                              ),
                            );
                          },
                          child: ColoredBox(
                            color: palette.fg.withValues(alpha: 0.28),
                            child: const SizedBox(
                              height: 2,
                              width: double.infinity,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _ToastPalette _paletteFor(SelloToastKind kind) {
    return switch (kind) {
      SelloToastKind.success => const _ToastPalette(
          icon: Icons.check_rounded,
          fg: AppColors.success,
          soft: AppColors.successContainer,
        ),
      SelloToastKind.warning => const _ToastPalette(
          icon: Icons.priority_high_rounded,
          fg: AppColors.warning,
          soft: AppColors.warningContainer,
        ),
      SelloToastKind.error => const _ToastPalette(
          icon: Icons.error_outline_rounded,
          fg: AppColors.error,
          soft: AppColors.errorContainer,
        ),
      SelloToastKind.info => const _ToastPalette(
          icon: Icons.info_outline_rounded,
          fg: AppColors.info,
          soft: AppColors.infoContainer,
        ),
    };
  }
}

class _ToastIcon extends StatelessWidget {
  const _ToastIcon({required this.palette});

  final _ToastPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: palette.soft,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(palette.icon, size: 18, color: palette.fg),
    );
  }
}

class _ToastCloseButton extends StatelessWidget {
  const _ToastCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        hoverColor: AppColors.surfaceMuted,
        splashColor: AppColors.veil,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: AppColors.textFaint,
          ),
        ),
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.message,
    this.title,
  });

  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title != null && title!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hasTitle ? title!.trim() : message,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: AppColors.textPrimary,
          ),
        ),
        if (hasTitle) ...[
          const SizedBox(height: 2),
          Text(
            message,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _ToastPalette {
  const _ToastPalette({
    required this.icon,
    required this.fg,
    required this.soft,
  });

  final IconData icon;
  final Color fg;
  final Color soft;
}
