import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/product_image.dart';

/// A single high-resolution photo for the fullscreen presentation viewer.
class SelloPhotoSource {
  const SelloPhotoSource({
    this.networkUrl,
    this.bytes,
  });

  final String? networkUrl;
  final Uint8List? bytes;

  bool get hasPreview =>
      bytes != null || (networkUrl != null && networkUrl!.isNotEmpty);

  factory SelloPhotoSource.fromDraft(MediaGalleryDraft draft) {
    return SelloPhotoSource(
      networkUrl: draft.networkUrl,
      bytes: draft.localBytes,
    );
  }

  factory SelloPhotoSource.fromProductImage(ProductImage image) {
    return SelloPhotoSource(
      networkUrl: image.networkUrl,
      bytes: image.localBytes,
    );
  }
}

/// Premium Photos-style fullscreen viewer for sales presentation.
///
/// Pinch / double-tap zoom, pan while zoomed, horizontal swipe between images,
/// swipe-down dismiss, and a page indicator when more than one image exists.
Future<void> showSelloPhotoViewer(
  BuildContext context, {
  required List<SelloPhotoSource> images,
  int initialIndex = 0,
}) {
  final active = images.where((image) => image.hasPreview).toList();
  if (active.isEmpty) return Future.value();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: AppDurations.normal,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _SelloPhotoViewer(
        images: active,
        initialIndex: initialIndex.clamp(0, active.length - 1),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppCurves.emphasized,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Hub-compatible entry that forwards gallery drafts into [showSelloPhotoViewer].
Future<void> showSelloImageLightbox(
  BuildContext context, {
  required List<MediaGalleryDraft> images,
  int initialIndex = 0,
}) {
  return showSelloPhotoViewer(
    context,
    images: [
      for (final image in images)
        if (!image.removed && image.hasPreview) SelloPhotoSource.fromDraft(image),
    ],
    initialIndex: initialIndex,
  );
}

class _SelloPhotoViewer extends StatefulWidget {
  const _SelloPhotoViewer({
    required this.images,
    required this.initialIndex,
  });

  final List<SelloPhotoSource> images;
  final int initialIndex;

  @override
  State<_SelloPhotoViewer> createState() => _SelloPhotoViewerState();
}

class _SelloPhotoViewerState extends State<_SelloPhotoViewer>
    with SingleTickerProviderStateMixin {
  static const double _dismissDistance = 140;
  static const double _doubleTapScale = 2.6;

  late final PageController _pageController;
  late int _index;
  late final AnimationController _dismissSnap;

  final Map<int, TransformationController> _transformers = {};
  final Map<int, VoidCallback> _scaleListeners = {};

  double _dragOffset = 0;
  bool _dragging = false;
  bool _zoomed = false;
  Offset? _doubleTapLocal;

  bool get _multi => widget.images.length > 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
    _dismissSnap = AnimationController(
      vsync: this,
      duration: AppDurations.fast,
    )..addListener(() {
        if (!_dragging) {
          setState(() {
            _dragOffset = _dragOffset * (1 - _dismissSnap.value);
          });
        }
      });
    _attachScaleListener(_index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _dismissSnap.dispose();
    for (final entry in _scaleListeners.entries) {
      _transformers[entry.key]?.removeListener(entry.value);
    }
    for (final controller in _transformers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _transformerFor(int index) {
    return _transformers.putIfAbsent(index, TransformationController.new);
  }

  void _attachScaleListener(int index) {
    if (_scaleListeners.containsKey(index)) return;
    final controller = _transformerFor(index);
    void listener() {
      if (index != _index || !mounted) return;
      final zoomed = controller.value.getMaxScaleOnAxis() > 1.05;
      if (zoomed != _zoomed) {
        setState(() => _zoomed = zoomed);
      }
    }

    _scaleListeners[index] = listener;
    controller.addListener(listener);
  }

  void _resetZoom(int index) {
    final controller = _transformerFor(index);
    controller.value = Matrix4.identity();
    if (index == _index && _zoomed) {
      setState(() => _zoomed = false);
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.images.length) return;
    _pageController.animateToPage(
      index,
      duration: AppDurations.normal,
      curve: AppCurves.standard,
    );
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_zoomed) return;
    _dismissSnap.stop();
    setState(() => _dragging = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_zoomed || !_dragging) return;
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_zoomed) return;
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        _dragOffset.abs() > _dismissDistance || velocity.abs() > 900;
    if (shouldDismiss) {
      _close();
      return;
    }
    setState(() => _dragging = false);
    _dismissSnap
      ..value = 0
      ..forward();
  }

  void _handleDoubleTap() {
    final controller = _transformerFor(_index);
    final current = controller.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      controller.value = Matrix4.identity();
      setState(() => _zoomed = false);
      return;
    }

    final tap = _doubleTapLocal ?? Alignment.center.alongSize(
      MediaQuery.sizeOf(context),
    );
    final matrix = Matrix4.identity()
      ..translateByDouble(tap.dx, tap.dy, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1)
      ..translateByDouble(-tap.dx, -tap.dy, 0, 1);
    controller.value = matrix;
    setState(() => _zoomed = true);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goTo(_index - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goTo(_index + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double get _backdropOpacity {
    final progress = (_dragOffset.abs() / _dismissDistance).clamp(0.0, 1.0);
    return 0.96 * (1 - progress * 0.55);
  }

  @override
  Widget build(BuildContext context) {
    final showChrome = context.isTablet || context.isDesktop;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black.withValues(alpha: _backdropOpacity)),
            Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Transform.scale(
                scale: (1 - (_dragOffset.abs() / 1200)).clamp(0.86, 1.0),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.images.length,
                  physics: _zoomed || _dragging
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  onPageChanged: (value) {
                    _resetZoom(_index);
                    setState(() {
                      _index = value;
                      _dragOffset = 0;
                      _dragging = false;
                    });
                    _attachScaleListener(value);
                    _resetZoom(value);
                  },
                  itemBuilder: (context, index) {
                    return _ZoomablePhotoPage(
                      image: widget.images[index],
                      transformationController: _transformerFor(index),
                      panEnabled: index == _index && _zoomed,
                      enableDismissGestures: index == _index && !_zoomed,
                      onDoubleTapDown: (details) {
                        _doubleTapLocal = details.localPosition;
                      },
                      onDoubleTap: _handleDoubleTap,
                      onVerticalDragStart: _onVerticalDragStart,
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      onVerticalDragEnd: _onVerticalDragEnd,
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  if (_multi)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          '${_index + 1} / ${widget.images.length}',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Close',
                          onPressed: _close,
                          iconSize: 22,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_multi && showChrome) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _NavChevron(
                    icon: Icons.chevron_left_rounded,
                    enabled: _index > 0,
                    onPressed: () => _goTo(_index - 1),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _NavChevron(
                    icon: Icons.chevron_right_rounded,
                    enabled: _index < widget.images.length - 1,
                    onPressed: () => _goTo(_index + 1),
                  ),
                ),
              ),
            ],
            if (_multi)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _PageDots(
                      count: widget.images.length,
                      index: _index,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhotoPage extends StatelessWidget {
  const _ZoomablePhotoPage({
    required this.image,
    required this.transformationController,
    required this.panEnabled,
    required this.enableDismissGestures,
    required this.onDoubleTapDown,
    required this.onDoubleTap,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final SelloPhotoSource image;
  final TransformationController transformationController;
  final bool panEnabled;
  final bool enableDismissGestures;
  final GestureTapDownCallback onDoubleTapDown;
  final VoidCallback onDoubleTap;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: onDoubleTapDown,
      onDoubleTap: onDoubleTap,
      onVerticalDragStart: enableDismissGestures ? onVerticalDragStart : null,
      onVerticalDragUpdate: enableDismissGestures ? onVerticalDragUpdate : null,
      onVerticalDragEnd: enableDismissGestures ? onVerticalDragEnd : null,
      child: Center(
        child: InteractiveViewer(
          transformationController: transformationController,
          minScale: 1,
          maxScale: 5,
          panEnabled: panEnabled,
          clipBehavior: Clip.none,
          child: _PhotoImage(image: image),
        ),
      ),
    );
  }
}

class _PhotoImage extends StatelessWidget {
  const _PhotoImage({required this.image});

  final SelloPhotoSource image;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Keep portrait packaging readable while preserving the uploaded ratio.
    final maxWidth = math.min(size.width, size.height * MediaConstants.aspectRatio);

    Widget child;
    if (image.bytes != null) {
      child = Image.memory(
        image.bytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );
    } else if (image.networkUrl != null && image.networkUrl!.isNotEmpty) {
      child = Image.network(
        image.networkUrl!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        // Intentionally no cacheWidth — fullscreen needs the full signed asset.
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: maxWidth,
            height: maxWidth / MediaConstants.aspectRatio,
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white54,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, error, stackTrace) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 48,
        ),
      );
    } else {
      child = const Icon(Icons.image_outlined, color: Colors.white54, size: 48);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: size.width,
        maxHeight: size.height,
      ),
      child: child,
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppCurves.standard,
            width: i == index ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ],
    );
  }
}

class _NavChevron extends StatelessWidget {
  const _NavChevron({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.04),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, color: enabled ? Colors.white : Colors.white38),
      ),
    );
  }
}
