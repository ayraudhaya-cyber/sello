import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;

/// Opens the browser's native colour picker. Prefer [SelloWebColorSwatch]
/// so the click lands on a real `<input type="color">`.
Future<String?> pickBrowserColor(String currentHex) {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'color'
    ..value = cssHex(currentHex);
  input.style
    ..position = 'fixed'
    ..left = '0'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0'
    ..border = '0'
    ..padding = '0'
    ..pointerEvents = 'none';

  web.document.body?.appendChild(input);

  void finish(String? value) {
    if (completer.isCompleted) return;
    input.remove();
    completer.complete(value);
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final value = input.value;
      finish(value.isEmpty ? null : value.toUpperCase());
    }.toJS,
  );
  input.addEventListener(
    'cancel',
    (web.Event _) {
      finish(null);
    }.toJS,
  );

  input.click();
  return completer.future;
}

String cssHex(String raw) {
  final value = raw.trim();
  if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) return value;
  return '#6C4FF2';
}

/// Flutter-drawn swatch with an invisible native colour input on top.
class SelloWebColorSwatch extends StatefulWidget {
  const SelloWebColorSwatch({
    super.key,
    required this.hex,
    required this.enabled,
    required this.onPicked,
    required this.child,
  });

  final String hex;
  final bool enabled;
  final ValueChanged<String> onPicked;
  final Widget child;

  @override
  State<SelloWebColorSwatch> createState() => _SelloWebColorSwatchState();
}

class _SelloWebColorSwatchState extends State<SelloWebColorSwatch> {
  web.HTMLInputElement? _input;

  @override
  void didUpdateWidget(covariant SelloWebColorSwatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hex != widget.hex) {
      _input?.value = cssHex(widget.hex);
    }
    _input?.disabled = !widget.enabled;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.enabled)
            HtmlElementView.fromTagName(
              tagName: 'input',
              isVisible: false,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              onElementCreated: (element) {
                final input = element as web.HTMLInputElement;
                _input = input;
                input
                  ..type = 'color'
                  ..value = cssHex(widget.hex)
                  ..title = 'Pick colour';
                input.style
                  ..width = '44px'
                  ..height = '44px'
                  ..margin = '0'
                  ..padding = '0'
                  ..border = '0'
                  ..cursor = 'pointer'
                  ..display = 'block';
                input.addEventListener(
                  'change',
                  (web.Event _) {
                    final value = input.value;
                    if (value.isEmpty) return;
                    widget.onPicked(value.toUpperCase());
                  }.toJS,
                );
              },
            ),
        ],
      ),
    );
  }
}
