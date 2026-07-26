import 'package:flutter/painting.dart';

/// Corner radii for the design system.
abstract final class AppRadius {
  static const double button = 12;
  static const double input = 12;
  static const double chip = 10;
  static const double card = 16;
  static const double dialog = 20;
  static const double bottomSheet = 24;
  static const double pill = 999;

  static const BorderRadius buttonAll = BorderRadius.all(
    Radius.circular(button),
  );

  static const BorderRadius inputAll = BorderRadius.all(
    Radius.circular(input),
  );

  static const BorderRadius cardAll = BorderRadius.all(
    Radius.circular(card),
  );

  static const BorderRadius dialogAll = BorderRadius.all(
    Radius.circular(dialog),
  );

  static const BorderRadius bottomSheetAll = BorderRadius.vertical(
    top: Radius.circular(bottomSheet),
  );
}
