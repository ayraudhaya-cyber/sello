import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

/// Release notes shipped inside this build.
///
/// The “Sello updated” card must describe the version that was just installed.
/// A remote file can still be an older publish, which is how the first notes
/// kept appearing on later versions.
abstract final class BundledReleaseNotes {
  static const assetPath = 'releases/sello-release.json';

  static Future<String?> forInstalled({
    required AppVersion installed,
    required ReleaseAppKind app,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      return notesFor(rawJson: raw, installed: installed, app: app);
    } catch (_) {
      return null;
    }
  }

  static String? notesFor({
    required String rawJson,
    required AppVersion installed,
    required ReleaseAppKind app,
  }) {
    final manifest = SelloReleaseManifest.tryParse(
      jsonDecode(rawJson),
      app: app,
    );
    if (manifest == null) return null;
    if (manifest.latest.identity != installed.identity) return null;
    final notes = manifest.notes?.trim();
    if (notes == null || notes.isEmpty) return null;
    return notes;
  }
}
