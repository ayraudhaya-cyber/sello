import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sello/features/devtools/presentation/dev_experience_host.dart';

export 'package:sello/features/devtools/presentation/dev_experience_host.dart'
    show
        DevExperienceBootstrap,
        DevExperienceToolbarButton,
        showDevExperienceDialog;

/// Auto-login bootstrap only — no floating overlay (avoids builder layout bugs).
Widget wrapWithDevExperience(Widget child) {
  if (kReleaseMode) return child;
  return DevExperienceBootstrap(child: child);
}
