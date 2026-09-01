import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/repositories/product_repository.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/country_catalog.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/media/sello_image_lightbox.dart';
import 'package:sello/shared/widgets/states/sello_empty_state.dart';

/// Opens the Photos-style viewer for a product's full gallery.
///
/// Loads signed high-resolution images first so zoom stays sharp.
Future<void> openSelloProductPhotoViewer(
  BuildContext context, {
  required ProductSummary product,
  int initialIndex = 0,
  List<SelloPhotoSource>? preloaded,
  ProductRepository? repository,
}) async {
  List<SelloPhotoSource> images = preloaded ?? const [];

  if (images.isEmpty) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black45,
      builder: (_) => const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
    try {
      images = await loadSelloProductPhotos(product, repository: repository);
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  if (!context.mounted || images.isEmpty) return;
  await showSelloPhotoViewer(
    context,
    images: images,
    initialIndex: initialIndex.clamp(0, images.length - 1),
  );
}

Future<List<SelloPhotoSource>> loadSelloProductPhotos(
  ProductSummary product, {
  ProductRepository? repository,
}) async {
  try {
    final rows =
        await (repository ?? ProductRepository()).media.fetchForProduct(
              product.id,
            );
    final images = <SelloPhotoSource>[
      for (final row in rows)
        if (row.hasPreview) SelloPhotoSource.fromProductImage(row),
    ];
    if (images.isNotEmpty) return images;
  } catch (_) {}

  if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
    return [SelloPhotoSource(networkUrl: product.imageUrl)];
  }
  return const [];
}

/// Sales-rep product presentation sheet — browse details, open photos fullscreen.
Future<void> showSelloProductPresentSheet(
  BuildContext context, {
  required ProductSummary product,
  String currencySymbol = '\$',
  ProductRepository? repository,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Theme enables a Material drag handle; this sheet draws its own.
    showDragHandle: false,
    builder: (context) {
      return _SelloProductPresentSheet(
        product: product,
        currencySymbol: currencySymbol,
        repository: repository,
      );
    },
  );
}

class _SelloProductPresentSheet extends ConsumerStatefulWidget {
  const _SelloProductPresentSheet({
    required this.product,
    required this.currencySymbol,
    this.repository,
  });

  final ProductSummary product;
  final String currencySymbol;
  final ProductRepository? repository;

  @override
  ConsumerState<_SelloProductPresentSheet> createState() =>
      _SelloProductPresentSheetState();
}

class _SelloProductPresentSheetState
    extends ConsumerState<_SelloProductPresentSheet> {
  List<SelloPhotoSource> _photos = const [];
  bool _loading = true;
  int _previewIndex = 0;

  ProductSummary get product => widget.product;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await loadSelloProductPhotos(
      product,
      repository: widget.repository,
    );
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _loading = false;
      _previewIndex = 0;
    });
  }

  Future<void> _openViewer(int index) async {
    if (_photos.isEmpty) return;
    await openSelloProductPhotoViewer(
      context,
      product: product,
      initialIndex: index,
      preloaded: _photos,
      repository: widget.repository,
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.92;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height, maxWidth: 720),
        child: Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlinePanel,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Present product',
                        style: context.texts.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    _PresentHero(
                      product: product,
                      photos: _photos,
                      loading: _loading,
                      index: _previewIndex,
                      onIndexChanged: (value) {
                        setState(() => _previewIndex = value);
                      },
                      onOpenViewer: _openViewer,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      product.name,
                      style: context.texts.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        product.sku,
                        if (product.categoryName != null) product.categoryName!,
                      ].join(' · '),
                      style: context.texts.bodyMedium?.copyWith(
                        color: context.selloColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      SelloFormatters.currency(
                        product.sellingPrice,
                        symbol: widget.currencySymbol,
                      ),
                      style: context.texts.headlineMedium?.copyWith(
                        color: context.brandAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${SelloFormatters.quantity(product.currentStockQuantity)} '
                      '${product.unitLabel?.trim().isNotEmpty == true ? product.unitLabel : 'units'} in stock',
                      style: context.texts.bodyMedium?.copyWith(
                        color: context.selloColors.textSecondary,
                      ),
                    ),
                    ..._buildCatalogSpecs(context),
                    if (product.description != null &&
                        product.description!.trim().isNotEmpty &&
                        (ref.watch(productFieldConfigProvider).valueOrNull
                                ?.isEnabled('description') ??
                            true)) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'About',
                        style: context.texts.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        product.description!.trim(),
                        style: context.texts.bodyMedium?.copyWith(
                          height: 1.45,
                          color: context.selloColors.textSecondary,
                        ),
                      ),
                    ],
                    if (!_loading && _photos.isEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      const SelloEmptyState(
                        title: 'No product photos yet',
                        message:
                            'Ask your manager to add packaging photos so you can present details to buyers.',
                        icon: Icons.photo_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCatalogSpecs(BuildContext context) {
    final config = ref.watch(productFieldConfigProvider).valueOrNull;
    if (config == null) return const [];

    final rows = <Widget>[];
    for (final field in config.forCatalog) {
      final value = _productFieldValue(product, field);
      if (value == null || value.trim().isEmpty) continue;
      final display = field.definition.fieldType == ProductFieldType.country
          ? CountryCatalog.display(value)
          : value;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  field.label,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.selloColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  display,
                  style: context.texts.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.lg),
      Text(
        'Product Details',
        style: context.texts.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      ...rows,
    ];
  }
}

String? _productFieldValue(ProductSummary product, CompanyProductField field) {
  return switch (field.fieldKey) {
    'barcode' => product.barcode,
    'brand' => product.brand,
    'unit_label' => product.unitLabel,
    'description' => product.description,
    'reorder_level' => product.reorderLevel?.toString(),
    _ => product.attribute(field.fieldKey),
  };
}

class _PresentHero extends StatefulWidget {
  const _PresentHero({
    required this.product,
    required this.photos,
    required this.loading,
    required this.index,
    required this.onIndexChanged,
    required this.onOpenViewer,
  });

  final ProductSummary product;
  final List<SelloPhotoSource> photos;
  final bool loading;
  final int index;
  final ValueChanged<int> onIndexChanged;
  final ValueChanged<int> onOpenViewer;

  @override
  State<_PresentHero> createState() => _PresentHeroState();
}

class _PresentHeroState extends State<_PresentHero> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.index);
  }

  @override
  void didUpdateWidget(covariant _PresentHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photos.length != widget.photos.length &&
        widget.photos.isNotEmpty &&
        _pageController.hasClients) {
      final page = widget.index.clamp(0, widget.photos.length - 1);
      _pageController.jumpToPage(page);
    } else if (oldWidget.index != widget.index &&
        _pageController.hasClients &&
        _pageController.page?.round() != widget.index) {
      _pageController.animateToPage(
        widget.index,
        duration: AppDurations.fast,
        curve: AppCurves.standard,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (widget.photos.isEmpty) return;
    final next = index.clamp(0, widget.photos.length - 1);
    widget.onIndexChanged(next);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        next,
        duration: AppDurations.fast,
        curve: AppCurves.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final multi = photos.length > 1;
    final index = widget.index.clamp(
      0,
      photos.isEmpty ? 0 : photos.length - 1,
    );

    return Column(
      children: [
        AspectRatio(
          aspectRatio: MediaConstants.aspectRatio,
          child: Material(
            color: AppColors.veil,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: widget.loading
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : photos.isEmpty
                    ? _Placeholder(name: widget.product.name)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          // Horizontal carousel — claim swipes ahead of the
                          // parent ListView so sales reps can flip photos.
                          NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              // Absorb vertical-competing notifications from
                              // PageView so the sheet ListView doesn't steal.
                              return notification.depth == 0 &&
                                  notification is ScrollUpdateNotification &&
                                  (notification.scrollDelta?.abs() ?? 0) > 0;
                            },
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: photos.length,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              onPageChanged: widget.onIndexChanged,
                              itemBuilder: (context, pageIndex) {
                                return GestureDetector(
                                  onTap: () =>
                                      widget.onOpenViewer(pageIndex),
                                  child: _HeroPhoto(
                                    photo: photos[pageIndex],
                                  ),
                                );
                              },
                            ),
                          ),
                          if (multi) ...[
                            Positioned(
                              left: 8,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _CarouselChevron(
                                  icon: Icons.chevron_left_rounded,
                                  enabled: index > 0,
                                  onTap: () => _goTo(index - 1),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _CarouselChevron(
                                  icon: Icons.chevron_right_rounded,
                                  enabled: index < photos.length - 1,
                                  onTap: () => _goTo(index + 1),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    '${index + 1} / ${photos.length}',
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: GestureDetector(
                              onTap: () => widget.onOpenViewer(index),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.fullscreen_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'View',
                                        style: TextStyle(
                                          fontFamily: AppTypography.fontFamily,
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
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
          ),
        ),
        if (multi) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < photos.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _goTo(i),
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    width: i == index ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == index
                          ? context.brandAccent
                          : AppColors.outlinePanel,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, thumbIndex) {
                final selected = thumbIndex == index;
                return GestureDetector(
                  onTap: () => _goTo(thumbIndex),
                  onDoubleTap: () => widget.onOpenViewer(thumbIndex),
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    width: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? context.brandAccent
                            : AppColors.outlinePanel,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _HeroPhoto(photo: photos[thumbIndex]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Swipe photo · tap arrows or thumbs · View for fullscreen',
            textAlign: TextAlign.center,
            style: context.texts.labelSmall?.copyWith(
              color: context.selloColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _CarouselChevron extends StatelessWidget {
  const _CarouselChevron({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.4 : 0.15),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _HeroPhoto extends StatelessWidget {
  const _HeroPhoto({required this.photo});

  final SelloPhotoSource photo;

  @override
  Widget build(BuildContext context) {
    if (photo.bytes != null) {
      return Image.memory(photo.bytes!, fit: BoxFit.cover);
    }
    if (photo.networkUrl != null && photo.networkUrl!.isNotEmpty) {
      return Image.network(
        photo.networkUrl!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.veil),
      );
    }
    return const ColoredBox(color: AppColors.veil);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.primarySoft),
      child: Center(
        child: Text(
          initial,
          style: context.texts.displaySmall?.copyWith(
            color: context.brandAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
