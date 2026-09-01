import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/feedback/sello_feedback.dart';

/// Reusable media gallery — large selected preview + horizontal thumb strip.
///
/// Images appear immediately; optimization runs in the background so the
/// surrounding form stays interactive.
class SelloProductMediaGallery extends StatefulWidget {
  const SelloProductMediaGallery({
    super.key,
    required this.items,
    required this.onChanged,
    this.onProcessingChanged,
    this.progress,
    this.title = 'Product Photos',
    this.maxImages = MediaConstants.kMaxProductImages,
    this.readOnly = false,
    this.showcase = false,
    this.onPreviewTap,
  });

  final List<MediaGalleryDraft> items;
  final ValueChanged<List<MediaGalleryDraft>> onChanged;

  /// Fired whenever any slot starts/finishes background optimization.
  final ValueChanged<bool>? onProcessingChanged;

  final MediaUploadProgress? progress;
  final String title;
  final int maxImages;

  /// Preview + thumb selection only — no add, crop, delete, or reorder.
  final bool readOnly;

  /// Larger preview, generous padding, quieter chrome (detail profiles).
  final bool showcase;

  /// Invoked when the large preview is tapped (e.g. open lightbox).
  /// Receives the selected image index among active items.
  final ValueChanged<int>? onPreviewTap;

  @override
  State<SelloProductMediaGallery> createState() =>
      _SelloProductMediaGalleryState();
}

class _SelloProductMediaGalleryState extends State<SelloProductMediaGallery> {
  final _media = MediaService();
  final Set<String> _optimizeJobs = {};
  late List<MediaGalleryDraft> _items;
  String? _selectedId;
  bool _picking = false;
  bool _previewActionsVisible = false;
  bool _emitting = false;

  List<MediaGalleryDraft> get _active =>
      _items.where((i) => !i.removed).toList()
        ..sort((a, b) {
          if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
          return a.sortOrder.compareTo(b.sortOrder);
        });

  MediaGalleryDraft? get _selected {
    final active = _active;
    if (active.isEmpty) return null;
    final match = active.where((i) => i.clientId == _selectedId);
    return match.isEmpty ? active.first : match.first;
  }

  bool get _atCapacity => _active.length >= widget.maxImages;

  @override
  void initState() {
    super.initState();
    _items = List<MediaGalleryDraft>.from(widget.items);
    _selectedId = _active.isEmpty ? null : _active.first.clientId;
  }

  @override
  void didUpdateWidget(covariant SelloProductMediaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external loads (e.g. edit product fetch) without clobbering
    // in-flight local optimization updates.
    if (!_emitting && !identical(widget.items, oldWidget.items)) {
      _items = List<MediaGalleryDraft>.from(widget.items);
    }
    final active = _active;
    if (active.isEmpty) {
      _selectedId = null;
    } else if (_selectedId == null ||
        !active.any((i) => i.clientId == _selectedId)) {
      _selectedId = active.first.clientId;
    }
  }

  void _emit(List<MediaGalleryDraft> next) {
    final normalized = _normalize(next);
    _emitting = true;
    setState(() => _items = normalized);
    widget.onChanged(normalized);
    _emitting = false;
    final processing = normalized.any((i) => !i.removed && i.processing);
    widget.onProcessingChanged?.call(processing);
  }

  void _patchItem(
    String clientId,
    MediaGalleryDraft Function(MediaGalleryDraft) transform,
  ) {
    if (!_items.any((d) => d.clientId == clientId)) return;
    final next = _items.map((d) {
      if (d.clientId != clientId) return d;
      return transform(d);
    }).toList();
    _emit(next);
  }

  Future<void> _addPhotos() async {
    if (_atCapacity || _picking) return;
    setState(() => _picking = true);

    try {
      final remaining = widget.maxImages - _active.length;
      final files = await _media.pickPhotos(
        context,
        remainingSlots: remaining,
      );

      // Unlock the form as soon as the OS picker closes.
      if (mounted) setState(() => _picking = false);
      if (files.isEmpty || !mounted) return;

      final limit = remaining.clamp(0, files.length);
      final selected = files.take(limit).toList();

      // Read all selected files, then show every thumbnail at once.
      final rawBytes = await Future.wait(
        selected.map((file) => file.readAsBytes()),
      );
      if (!mounted) return;

      var working = List<MediaGalleryDraft>.from(_items);
      final jobs = <({String id, Uint8List bytes})>[];
      var sortBase = working.where((d) => !d.removed).length;
      String? firstId;

      for (var i = 0; i < rawBytes.length; i++) {
        if (sortBase >= widget.maxImages) break;
        final id =
            'local_${DateTime.now().microsecondsSinceEpoch}_$i';
        firstId ??= id;
        jobs.add((id: id, bytes: rawBytes[i]));
        working = [
          ...working,
          MediaGalleryDraft.local(
            clientId: id,
            bytes: rawBytes[i],
            sortOrder: sortBase,
            isPrimary: sortBase == 0,
            processing: true,
            optimized: false,
          ),
        ];
        sortBase++;
      }

      if (jobs.isEmpty) return;

      setState(() => _selectedId = firstId);
      _emit(working);

      // Paint all thumbs, then optimize in the background without blocking.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      unawaited(_optimizeQueue(jobs));
    } catch (error) {
      if (!mounted) return;
      SelloSnackbars.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _optimizeQueue(
    List<({String id, Uint8List bytes})> jobs,
  ) async {
    for (final job in jobs) {
      if (!mounted) return;
      // Keep the event loop free so form fields stay interactive.
      await Future<void>.delayed(const Duration(milliseconds: 24));
      if (!mounted) return;
      await _optimizeInBackground(job.id, job.bytes);
    }
  }

  Future<void> _optimizeInBackground(
    String clientId,
    Uint8List rawBytes,
  ) async {
    if (_optimizeJobs.contains(clientId)) return;
    _optimizeJobs.add(clientId);

    try {
      final processed = await _media.compressImage(rawBytes);
      if (!mounted) return;

      final stillThere = _findDraft(clientId);
      if (stillThere == null || stillThere.removed) return;

      _patchItem(
        clientId,
        (d) => d.copyWith(
          localBytes: processed.bytes,
          processing: false,
          optimized: true,
          dirty: true,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _patchItem(
        clientId,
        (d) => d.copyWith(processing: false),
      );
      SelloSnackbars.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      _optimizeJobs.remove(clientId);
    }
  }

  MediaGalleryDraft? _findDraft(String clientId) {
    for (final d in _items) {
      if (d.clientId == clientId) return d;
    }
    return null;
  }

  Future<void> _editCrop(MediaGalleryDraft item) async {
    if (item.processing) return;

    try {
      final source = await _media.resolvePreviewBytes(
        localBytes: item.localBytes,
        networkUrl: item.networkUrl,
      );
      if (source == null || !mounted) {
        if (mounted) {
          SelloSnackbars.error(context, 'Unable to load that photo for cropping.');
        }
        return;
      }

      // Crop route opens immediately; skip heavy prepare when already optimized.
      final cropped = await _media.maybeCrop(
        context,
        source,
        alreadyOptimized: item.optimized ||
            (item.localBytes != null &&
                item.localBytes!.lengthInBytes <= 1024 * 1024),
      );
      if (cropped == null || !mounted) return;

      // Show cropped result right away; compress in the background.
      _patchItem(
        item.clientId,
        (d) => d.copyWith(
          localBytes: cropped,
          processing: true,
          optimized: false,
          dirty: true,
          clearNetworkUrl: true,
        ),
      );
      unawaited(_optimizeInBackground(item.clientId, cropped));
    } catch (error) {
      if (!mounted) return;
      SelloSnackbars.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void _delete(MediaGalleryDraft item) {
    final next = _items.map((d) {
      if (d.clientId != item.clientId) return d;
      if (d.remoteId == null) {
        return d.copyWith(
          removed: true,
          processing: false,
          clearLocalBytes: true,
        );
      }
      return d.copyWith(removed: true, dirty: true, processing: false);
    }).toList();

    if (_selectedId == item.clientId) {
      final remaining = next.where((d) => !d.removed).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _selectedId = remaining.isEmpty ? null : remaining.first.clientId;
    }
    _emit(next);
  }

  void _onReorder(int oldIndex, int newIndex) {
    final active = List<MediaGalleryDraft>.from(_active);
    if (oldIndex == newIndex) return;
    final moved = active.removeAt(oldIndex);
    active.insert(newIndex.clamp(0, active.length), moved);

    final byId = {for (final d in _items) d.clientId: d};
    final rebuilt = <MediaGalleryDraft>[
      for (var i = 0; i < active.length; i++)
        byId[active[i].clientId]!.copyWith(
          sortOrder: i,
          isPrimary: i == 0,
          dirty: true,
        ),
      ..._items.where((d) => d.removed),
    ];
    _emit(rebuilt);
  }

  void _select(MediaGalleryDraft item) {
    setState(() {
      _selectedId = item.clientId;
      _previewActionsVisible = false;
    });
  }

  List<MediaGalleryDraft> _normalize(List<MediaGalleryDraft> input) {
    final active = input.where((d) => !d.removed).toList()
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final normalizedActive = <MediaGalleryDraft>[
      for (var i = 0; i < active.length; i++)
        active[i].copyWith(sortOrder: i, isPrimary: i == 0),
    ];
    return [
      ...normalizedActive,
      ...input.where((d) => d.removed),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final active = _active;
    final isMobile = context.isMobile;
    final readOnly = widget.readOnly;
    final showcase = widget.showcase;
    final showThumbs = active.length > 1;
    final saveProgress = widget.progress;
    final showSaveProgress = !readOnly &&
        saveProgress != null &&
        saveProgress.phase != MediaUploadPhase.idle &&
        saveProgress.phase != MediaUploadPhase.success;
    final selectedIndex = selected == null
        ? 0
        : active.indexWhere((i) => i.clientId == selected.clientId).clamp(0, active.isEmpty ? 0 : active.length - 1);

    return Container(
      decoration: BoxDecoration(
        color: context.brandAccent.withValues(alpha: showcase ? 0.025 : 0.03),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      padding: EdgeInsets.all(
        showcase ? (isMobile ? 14 : 18) : (isMobile ? 12 : 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!showcase || !readOnly)
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.01 * 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (!readOnly)
                  Text(
                    '${active.length}/${widget.maxImages}',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textFaint,
                    ),
                  ),
              ],
            ),
          if (!showcase || !readOnly) const SizedBox(height: 10),
          _GalleryPreview(
            item: selected,
            picking: _picking,
            actionsVisible: _previewActionsVisible,
            emptyLabel: readOnly ? 'No product photos' : null,
            onTapEmpty: readOnly ? () {} : _addPhotos,
            onPreviewTap: selected == null || widget.onPreviewTap == null
                ? null
                : () => widget.onPreviewTap!(selectedIndex),
            onToggleActions: readOnly || !isMobile
                ? null
                : () => setState(
                      () => _previewActionsVisible = !_previewActionsVisible,
                    ),
            onEditCrop: readOnly ||
                    selected == null ||
                    selected.processing
                ? null
                : () => _editCrop(selected),
            onDelete: readOnly || selected == null
                ? null
                : () => _delete(selected),
          ),
          if (showSaveProgress) ...[
            const SizedBox(height: 8),
            Text(
              saveProgress.message ?? 'Saving photos…',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (showThumbs || (!readOnly && active.isNotEmpty)) ...[
            SizedBox(height: showcase ? 16 : 12),
            _SquareThumbStrip(
              active: active,
              selectedId: selected?.clientId,
              readOnly: readOnly,
              showcase: showcase,
              isMobile: isMobile,
              showAdd: !readOnly && !_atCapacity,
              addEnabled: !_picking,
              onAdd: _addPhotos,
              onSelect: _select,
              onDelete: _delete,
              onEditCrop: _editCrop,
              onReorder: readOnly ? null : _onReorder,
            ),
          ] else if (!readOnly && active.isEmpty) ...[
            const SizedBox(height: 12),
            SelloButton(
              label: 'Add Photos',
              icon: Icons.add_photo_alternate_outlined,
              variant: SelloButtonVariant.primary,
              onPressed: _picking ? null : _addPhotos,
            ),
          ],
        ],
      ),
    );
  }
}

class _SquareThumbStrip extends StatelessWidget {
  const _SquareThumbStrip({
    required this.active,
    required this.selectedId,
    required this.readOnly,
    required this.showcase,
    required this.isMobile,
    required this.showAdd,
    required this.addEnabled,
    required this.onAdd,
    required this.onSelect,
    required this.onDelete,
    required this.onEditCrop,
    this.onReorder,
  });

  final List<MediaGalleryDraft> active;
  final String? selectedId;
  final bool readOnly;
  final bool showcase;
  final bool isMobile;
  final bool showAdd;
  final bool addEnabled;
  final VoidCallback onAdd;
  final ValueChanged<MediaGalleryDraft> onSelect;
  final ValueChanged<MediaGalleryDraft> onDelete;
  final ValueChanged<MediaGalleryDraft> onEditCrop;
  final void Function(int oldIndex, int newIndex)? onReorder;

  static const double _gap = 8;
  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    final slotCount = active.length + (showAdd ? 1 : 0);
    if (slotCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            (constraints.maxWidth - _gap * (slotCount - 1)) / slotCount;

        Widget thumbAt(int index) {
          final item = active[index];
          final thumb = _ThumbTile(
            item: item,
            isPrimary: index == 0,
            isSelected: item.clientId == selectedId,
            showActionsAlways: !readOnly && isMobile,
            readOnly: readOnly,
            elevateOnHover: readOnly || showcase,
            onSelect: () => onSelect(item),
            onDelete: () => onDelete(item),
            onEditCrop: () => onEditCrop(item),
          );

          if (readOnly || onReorder == null) return thumb;

          return isMobile
              ? ReorderableDelayedDragStartListener(index: index, child: thumb)
              : ReorderableDragStartListener(index: index, child: thumb);
        }

        if (readOnly || onReorder == null) {
          return SizedBox(
            height: side,
            child: Row(
              children: [
                for (var i = 0; i < active.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  SizedBox(
                    width: side,
                    height: side,
                    child: thumbAt(i),
                  ),
                ],
                if (showAdd) ...[
                  if (active.isNotEmpty) const SizedBox(width: _gap),
                  SizedBox(
                    width: side,
                    height: side,
                    child: _AddThumbSlot(
                      enabled: addEnabled,
                      onTap: onAdd,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return SizedBox(
          height: side,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final t = Curves.easeOut.transform(animation.value);
                  return Material(
                    elevation: 2 + 4 * t,
                    color: Colors.transparent,
                    shadowColor: context.brandAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(_radius),
                    child: child,
                  );
                },
                child: child,
              );
            },
            itemCount: slotCount,
            onReorderItem: (oldIndex, newIndex) {
              if (showAdd && (oldIndex >= active.length || newIndex >= active.length)) {
                return;
              }
              onReorder!(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              if (showAdd && index == active.length) {
                return Padding(
                  key: const ValueKey('add_slot'),
                  padding: EdgeInsets.only(left: active.isEmpty ? 0 : _gap),
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: _AddThumbSlot(
                      enabled: addEnabled,
                      onTap: onAdd,
                    ),
                  ),
                );
              }

              return Padding(
                key: ValueKey(active[index].clientId),
                padding: EdgeInsets.only(left: index == 0 ? 0 : _gap),
                child: SizedBox(
                  width: side,
                  height: side,
                  child: thumbAt(index),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GalleryPreview extends StatefulWidget {
  const _GalleryPreview({
    required this.item,
    required this.picking,
    required this.actionsVisible,
    required this.onTapEmpty,
    this.emptyLabel,
    this.onPreviewTap,
    this.onToggleActions,
    this.onEditCrop,
    this.onDelete,
  });

  final MediaGalleryDraft? item;
  final bool picking;
  final bool actionsVisible;
  final VoidCallback onTapEmpty;
  final String? emptyLabel;
  final VoidCallback? onPreviewTap;
  final VoidCallback? onToggleActions;
  final VoidCallback? onEditCrop;
  final VoidCallback? onDelete;

  @override
  State<_GalleryPreview> createState() => _GalleryPreviewState();
}

class _GalleryPreviewState extends State<_GalleryPreview> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showActions = widget.item != null &&
        (widget.actionsVisible || _hovered) &&
        (widget.onEditCrop != null || widget.onDelete != null);

    VoidCallback? onTap;
    if (widget.item == null && !widget.picking) {
      onTap = widget.emptyLabel != null ? null : widget.onTapEmpty;
    } else if (widget.onPreviewTap != null) {
      onTap = widget.onPreviewTap;
    } else {
      onTap = widget.onToggleActions;
    }

    return AspectRatio(
      aspectRatio: MediaConstants.aspectRatio,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: widget.onPreviewTap != null && widget.item != null
            ? SystemMouseCursors.zoomIn
            : SystemMouseCursors.basic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Ink(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.outlinePanel),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md - 1),
                child: widget.item == null
                    ? _EmptyPreview(label: widget.emptyLabel)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          _ImagePreview(
                            bytes: widget.item!.localBytes,
                            networkUrl: widget.item!.networkUrl,
                          ),
                          if (widget.item!.processing)
                            const Positioned(
                              right: 10,
                              top: 10,
                              child: _ProcessingBadge(),
                            ),
                          if (widget.item!.isPrimary)
                            const Positioned(
                              left: 10,
                              top: 10,
                              child: _StarBadge(large: true),
                            ),
                          if (widget.onPreviewTap != null)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 140),
                                opacity: _hovered ? 1 : 0.72,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface
                                        .withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: AppShadows.level1,
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.open_in_full_rounded,
                                        size: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'View',
                                        style: TextStyle(
                                          fontFamily: AppTypography.fontFamily,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (showActions)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Row(
                                children: [
                                  if (widget.onEditCrop != null)
                                    _OverlayAction(
                                      tooltip: 'Crop',
                                      icon: Icons.crop_rounded,
                                      onPressed: widget.onEditCrop,
                                    ),
                                  if (widget.onEditCrop != null &&
                                      widget.onDelete != null)
                                    const SizedBox(width: 8),
                                  if (widget.onDelete != null)
                                    _OverlayAction(
                                      tooltip: 'Delete',
                                      icon: Icons.delete_outline_rounded,
                                      danger: true,
                                      onPressed: widget.onDelete,
                                    ),
                                ],
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
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final message = label ?? 'Add up to 3 product photos';
    final isReadOnly = label != null;
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.brandAccent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isReadOnly
                    ? Icons.image_outlined
                    : Icons.add_photo_alternate_outlined,
                size: 24,
                color: context.brandAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarBadge extends StatelessWidget {
  const _StarBadge({this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 28.0 : 20.0;
    final iconSize = large ? 15.0 : 11.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: AppShadows.level1,
      ),
      child: Icon(
        Icons.star_rounded,
        size: iconSize,
        color: context.brandAccent,
      ),
    );
  }
}

class _ProcessingBadge extends StatelessWidget {
  const _ProcessingBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 18.0 : 26.0;
    final stroke = compact ? 1.8 : 2.2;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(compact ? 3 : 5),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        boxShadow: AppShadows.level1,
      ),
      child: CircularProgressIndicator(
        strokeWidth: stroke,
        color: context.brandAccent,
      ),
    );
  }
}

class _OverlayAction extends StatelessWidget {
  const _OverlayAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          hoverColor: AppColors.veil,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 17,
              color: danger ? AppColors.attention : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbTile extends StatefulWidget {
  const _ThumbTile({
    required this.item,
    required this.isPrimary,
    required this.isSelected,
    required this.onSelect,
    required this.onDelete,
    required this.onEditCrop,
    this.showActionsAlways = false,
    this.readOnly = false,
    this.elevateOnHover = false,
  });

  final MediaGalleryDraft item;
  final bool isPrimary;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final VoidCallback onEditCrop;
  final bool showActionsAlways;
  final bool readOnly;
  final bool elevateOnHover;

  @override
  State<_ThumbTile> createState() => _ThumbTileState();
}

class _ThumbTileState extends State<_ThumbTile> {
  bool _hovered = false;

  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    final processing = widget.item.processing;
    final showActions = !widget.readOnly &&
        !processing &&
        (widget.showActionsAlways || _hovered);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            widget.elevateOnHover && _hovered ? -2 : 0,
            0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(
              color: widget.isSelected
                  ? context.brandAccent
                  : (_hovered
                      ? context.brandAccent.withValues(alpha: 0.35)
                      : AppColors.outlinePanel),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.elevateOnHover && _hovered
                ? [
                    BoxShadow(
                      color: context.brandAccent.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius - 1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ImagePreview(
                  bytes: widget.item.localBytes,
                  networkUrl: widget.item.networkUrl,
                ),
                if (processing)
                  const ColoredBox(
                    color: Color(0x28000000),
                  ),
                if (processing)
                  const Positioned(
                    right: 4,
                    bottom: 4,
                    child: _ProcessingBadge(compact: true),
                  ),
                if (widget.isPrimary)
                  const Positioned(
                    left: 3,
                    top: 3,
                    child: _StarBadge(),
                  ),
                if (showActions) ...[
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _ThumbIconButton(
                      tooltip: 'Delete',
                      icon: Icons.close_rounded,
                      onPressed: widget.onDelete,
                    ),
                  ),
                  Positioned(
                    left: 2,
                    bottom: 2,
                    child: _ThumbIconButton(
                      tooltip: 'Crop',
                      icon: Icons.crop_rounded,
                      onPressed: widget.onEditCrop,
                    ),
                  ),
                ],
                if (!widget.readOnly && processing)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _ThumbIconButton(
                      tooltip: 'Delete',
                      icon: Icons.close_rounded,
                      onPressed: widget.onDelete,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbIconButton extends StatelessWidget {
  const _ThumbIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          hoverColor: AppColors.veil,
          child: SizedBox(
            width: 20,
            height: 20,
            child: Icon(icon, size: 12, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _AddThumbSlot extends StatelessWidget {
  const _AddThumbSlot({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(_radius),
        hoverColor: AppColors.veil,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: AppColors.outlinePanel),
          ),
          child: Icon(
            Icons.add_rounded,
            size: 22,
            color: enabled ? context.brandAccent : AppColors.textFaint,
          ),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({this.bytes, this.networkUrl});

  final Uint8List? bytes;
  final String? networkUrl;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      // Decode at display size — full-res camera files freeze Chrome if painted raw.
      return Image.memory(
        bytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: 720,
      );
    }
    if (networkUrl != null && networkUrl!.isNotEmpty) {
      return Image.network(
        networkUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: AppColors.surfaceMuted,
          child: Icon(Icons.broken_image_outlined, color: AppColors.textFaint),
        ),
      );
    }
    return const ColoredBox(color: AppColors.surfaceMuted);
  }
}
