import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/inputs/sello_browser_color.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

/// Hex colour field with an HSV picker dialog (desktop) or sheet (mobile).
class SelloColorField extends StatefulWidget {
  const SelloColorField({
    super.key,
    required this.controller,
    required this.fallbackColor,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.required = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final Color fallbackColor;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final bool enabled;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;
  final ValueChanged<String>? onChanged;

  static String hexOf(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  State<SelloColorField> createState() => _SelloColorFieldState();
}

class _SelloColorFieldState extends State<SelloColorField> {
  Color get _swatchColor {
    final parsed = _parse(widget.controller.text);
    return parsed ?? widget.fallbackColor;
  }

  static Color? _parse(String raw) {
    final hex = ClientBranding.normalizeHex(raw);
    if (hex == null) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  void _applyColor(Color color) {
    final hex = SelloColorField.hexOf(color);
    if (widget.controller.text == hex) return;
    widget.controller.value = TextEditingValue(
      text: hex,
      selection: TextSelection.collapsed(offset: hex.length),
    );
    widget.onChanged?.call(hex);
    if (mounted) setState(() {});
  }

  Future<void> _openPicker() async {
    if (!widget.enabled) return;

    // Flutter web freezes if the custom HSV board lays out at infinite
    // width. Use the browser picker there — no overlay, no CustomPaint.
    if (kIsWeb) {
      final picked = await pickBrowserColor(SelloColorField.hexOf(_swatchColor));
      if (!mounted || picked == null) return;
      final parsed = _parse(picked);
      if (parsed != null) _applyColor(parsed);
      return;
    }

    if (context.isMobile) {
      await _openMobileSheet();
      return;
    }

    await _openDesktopDialog();
  }

  Future<void> _openDesktopDialog() async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.18),
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.mdAll,
            side: const BorderSide(color: AppColors.outlinePanel),
          ),
          child: SizedBox(
            width: _HsvPicker.boardWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.label ?? 'Choose colour',
                    style: context.texts.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  _HsvPicker(
                    color: _swatchColor,
                    onChanged: _applyColor,
                  ),
                  const SizedBox(height: 16),
                  SelloButton(
                    label: 'Done',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMobileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.bottomSheetAll,
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.label ?? 'Choose colour',
                    style: context.texts.titleMedium,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: _HsvPicker.boardWidth,
                  child: _HsvPicker(
                    color: _swatchColor,
                    onChanged: _applyColor,
                  ),
                ),
                const SizedBox(height: 16),
                SelloButton(
                  label: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = SelloTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      helperText: widget.helperText,
      enabled: widget.enabled,
      required: widget.required,
      inputFormatters: const [_HexColorFormatter()],
      onChanged: (value) {
        widget.onChanged?.call(value);
        setState(() {});
      },
    );

    // Keep the swatch outside the text field. On Flutter web, suffixIcon
    // taps are often swallowed by the field's focus hit-test.
    Widget swatch = Tooltip(
      message: 'Pick colour',
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled && !kIsWeb ? _openPicker : null,
          child: Semantics(
            button: true,
            enabled: widget.enabled,
            label: 'Pick colour',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _swatchColor,
                borderRadius: AppRadius.inputAll,
                border: Border.all(color: AppColors.outlineStrong),
                boxShadow: AppShadows.level1,
              ),
            ),
          ),
        ),
      ),
    );

    if (kIsWeb) {
      swatch = SelloWebColorSwatch(
        hex: SelloColorField.hexOf(_swatchColor),
        enabled: widget.enabled,
        onPicked: (hex) {
          final parsed = _parse(hex);
          if (parsed != null) _applyColor(parsed);
        },
        child: swatch,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: field),
            const SizedBox(width: 10),
            swatch,
          ],
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.errorText!,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              color: AppColors.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _HsvPicker extends StatefulWidget {
  const _HsvPicker({
    required this.color,
    required this.onChanged,
  });

  static const boardWidth = 280.0;

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<_HsvPicker> createState() => _HsvPickerState();
}

class _HsvPickerState extends State<_HsvPicker> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
  }

  @override
  void didUpdateWidget(covariant _HsvPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _hsv = HSVColor.fromColor(widget.color);
    }
  }

  void _set(HSVColor next) {
    setState(() => _hsv = next);
    widget.onChanged(next.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SvSquare(
          hsv: _hsv,
          onChanged: _set,
        ),
        const SizedBox(height: 14),
        _HueBar(
          hsv: _hsv,
          onChanged: _set,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlineStrong),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              SelloColorField.hexOf(_hsv.toColor()),
              style: context.texts.labelMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SvSquare extends StatelessWidget {
  const _SvSquare({
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _fromLocal(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    const width = _HsvPicker.boardWidth;
    const height = 148.0;
    const size = Size(width, height);
    return GestureDetector(
      onPanDown: (d) => _fromLocal(d.localPosition, size),
      onPanUpdate: (d) => _fromLocal(d.localPosition, size),
      child: CustomPaint(
        size: size,
        painter: _SvPainter(hue: hsv.hue),
        child: Stack(
          children: [
            Positioned(
              left: hsv.saturation * width - 7,
              top: (1 - hsv.value) * height - 7,
              child: IgnorePointer(
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hsv.toColor(),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                      ),
                    ],
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

class _SvPainter extends CustomPainter {
  const _SvPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(AppRadius.sm),
    );
    canvas.save();
    canvas.clipRRect(rrect);

    final sat = LinearGradient(
      colors: [
        HSVColor.fromAHSV(1, hue, 0, 1).toColor(),
        HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = sat.createShader(rect));

    final val = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0xFF000000)],
    );
    canvas.drawRect(rect, Paint()..shader = val.createShader(rect));
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.outlinePanel
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SvPainter oldDelegate) => oldDelegate.hue != hue;
}

class _HueBar extends StatelessWidget {
  const _HueBar({
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const _hues = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  void _fromLocal(Offset local, double width) {
    final hue = (local.dx / width).clamp(0.0, 1.0) * 359.9;
    onChanged(hsv.withHue(hue));
  }

  @override
  Widget build(BuildContext context) {
    const width = _HsvPicker.boardWidth;
    const height = 16.0;
    return GestureDetector(
      onPanDown: (d) => _fromLocal(d.localPosition, width),
      onPanUpdate: (d) => _fromLocal(d.localPosition, width),
      child: SizedBox(
        height: height,
        width: width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                gradient: const LinearGradient(colors: _hues),
                border: Border.all(color: AppColors.outlinePanel),
              ),
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: (hsv.hue / 359.9) * width - 8,
              top: -2,
              child: IgnorePointer(
                child: Container(
                  width: 16,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.outlineStrong),
                    boxShadow: AppShadows.level1,
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

class _HexColorFormatter extends TextInputFormatter {
  const _HexColorFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-F#]'), '');
    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    if (!text.startsWith('#')) {
      text = '#$text';
    }
    final hashCount = '#'.allMatches(text).length;
    if (hashCount > 1) {
      text = '#${text.replaceAll('#', '')}';
    }
    if (text.length > 7) {
      text = text.substring(0, 7);
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
