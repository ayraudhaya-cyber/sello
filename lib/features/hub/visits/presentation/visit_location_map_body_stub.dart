import 'package:flutter/material.dart';
import 'package:sello/features/hub/visits/presentation/visit_location_pins.dart';

/// Non-web hosts open the stored pin in the browser map.
class VisitLocationMapBody extends StatelessWidget {
  const VisitLocationMapBody({super.key, required this.pins});

  final List<VisitLocationPin> pins;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 220,
      child: Center(
        child: Text(
          'Open on map to see this location.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 13,
            color: Color(0xFF736C90),
          ),
        ),
      ),
    );
  }
}
