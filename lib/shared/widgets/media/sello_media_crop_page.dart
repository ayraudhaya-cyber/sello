import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/feedback/sello_feedback.dart';

/// Optional portrait crop (default 4:5).
///
/// Opens immediately with a loading state, then shows a downscaled image so
/// decode / apply stay responsive. Returns cropped bytes, or `null` on cancel.
class SelloMediaCropPage extends StatefulWidget {
  const SelloMediaCropPage({
    super.key,
    required this.loadBytes,
    this.aspectRatio = MediaConstants.aspectRatio,
  });

  /// Loads (and ideally downscales) bytes after the route is already visible.
  final Future<Uint8List> Function() loadBytes;
  final double aspectRatio;

  static Future<Uint8List?> open(
    BuildContext context, {
    required Future<Uint8List> Function() loadBytes,
    double aspectRatio = MediaConstants.aspectRatio,
  }) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SelloMediaCropPage(
          loadBytes: loadBytes,
          aspectRatio: aspectRatio,
        ),
      ),
    );
  }

  @override
  State<SelloMediaCropPage> createState() => _SelloMediaCropPageState();
}

class _SelloMediaCropPageState extends State<SelloMediaCropPage> {
  final _controller = CropController();
  Uint8List? _bytes;
  Object? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.loadBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.textPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.surface,
        title: const Text('Edit crop'),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Row(
              children: [
                Expanded(
                  child: SelloButton(
                    label: 'Cancel',
                    variant: SelloButtonVariant.outline,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelloButton(
                    label: 'Apply crop',
                    variant: SelloButtonVariant.primary,
                    loading: _busy,
                    onPressed: _bytes == null || _busy
                        ? null
                        : () {
                            setState(() => _busy = true);
                            _controller.crop();
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError.toString().replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.surface),
          ),
        ),
      );
    }

    if (_bytes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.surface,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Preparing photo…',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.surface,
              ),
            ),
          ],
        ),
      );
    }

    return Crop(
      image: _bytes!,
      controller: _controller,
      aspectRatio: widget.aspectRatio,
      withCircleUi: false,
      baseColor: AppColors.textPrimary,
      maskColor: Colors.black.withValues(alpha: 0.55),
      onCropped: (result) {
        if (!mounted) return;
        switch (result) {
          case CropSuccess(:final croppedImage):
            Navigator.of(context).pop(croppedImage);
          case CropFailure():
            setState(() => _busy = false);
            SelloSnackbars.error(context, 'Unable to crop that image.');
        }
      },
    );
  }
}
