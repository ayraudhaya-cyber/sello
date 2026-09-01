import 'package:flutter/painting.dart';

/// Corner radii for the Sello design language.
abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 10;
  /// Small / compact buttons.
  static const double buttonSm = 6;
  /// Medium / large buttons and form controls (search, inputs, filters).
  static const double button = 8;
  /// Text fields — same as [button] for toolbar / form consistency.
  static const double input = 8;
  static const double chip = 10;
  static const double icon = 11;
  /// Meta chips, segmented shells, list-row hover.
  static const double control = 12;
  static const double md = 14;
  /// Compact panels / list surfaces (Products toolbar, metric cards).
  static const double panel = 16;
  static const double card = 20;
  static const double dialog = 20;
  static const double xl = 26;
  static const double bottomSheet = 24;
  static const double pill = 999;

  static const BorderRadius buttonSmAll = BorderRadius.all(
    Radius.circular(buttonSm),
  );

  static const BorderRadius buttonAll = BorderRadius.all(
    Radius.circular(button),
  );

  static const BorderRadius inputAll = BorderRadius.all(
    Radius.circular(input),
  );

  static const BorderRadius iconAll = BorderRadius.all(
    Radius.circular(icon),
  );

  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );

  static const BorderRadius panelAll = BorderRadius.all(
    Radius.circular(panel),
  );

  static const BorderRadius cardAll = BorderRadius.all(
    Radius.circular(card),
  );

  static const BorderRadius mdAll = BorderRadius.all(
    Radius.circular(md),
  );

  static const BorderRadius dialogAll = BorderRadius.all(
    Radius.circular(dialog),
  );

  static const BorderRadius bottomSheetAll = BorderRadius.vertical(
    top: Radius.circular(bottomSheet),
  );
}
