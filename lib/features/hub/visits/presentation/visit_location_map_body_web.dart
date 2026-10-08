import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:sello/features/hub/visits/presentation/visit_location_pins.dart';
import 'package:web/web.dart' as web;

final Set<String> _registered = <String>{};

/// In-app map for stored visit coordinates. Web only.
class VisitLocationMapBody extends StatefulWidget {
  const VisitLocationMapBody({super.key, required this.pins});

  final List<VisitLocationPin> pins;

  @override
  State<VisitLocationMapBody> createState() => _VisitLocationMapBodyState();
}

class _VisitLocationMapBodyState extends State<VisitLocationMapBody> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    final html = visitLocationMapHtml(widget.pins);
    _viewType = 'visit-map-${html.hashCode}';
    if (_registered.add(_viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
        return web.HTMLIFrameElement()
          ..setAttribute('srcdoc', html)
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 260, child: HtmlElementView(viewType: _viewType));
  }
}
