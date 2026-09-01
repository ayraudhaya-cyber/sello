import 'package:flutter/material.dart';

/// VM / mobile stub — no browser colour input.
Future<String?> pickBrowserColor(String currentHex) async => null;

class SelloWebColorSwatch extends StatelessWidget {
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
  Widget build(BuildContext context) => child;
}
