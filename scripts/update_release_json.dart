// scripts/update_release_json.dart
// Updates the release manifest JSON files with new version/build/notes.
// Usage: dart run scripts/update_release_json.dart <version> <build> <date> [notes] [apps]

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('Usage: dart run scripts/update_release_json.dart <version> <build> <date> [notes] [apps]');
    exit(1);
  }

  final version = args[0];
  final build = int.parse(args[1]);
  final date = args[2];
  final notes = args.length > 3 ? args[3] : '';
  final appsArg = args.length > 4 ? args[4] : 'both';
  final apps = appsArg == 'both'
      ? ['sales_rep', 'owner_manager']
      : [appsArg];

  final files = ['releases/sello-release.json', 'web/sello-release.json'];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('File not found: $path');
      exit(1);
    }

    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final appsMap = json['apps'] as Map<String, dynamic>;

    for (final app in apps) {
      final entry = appsMap[app] as Map<String, dynamic>;
      final latest = entry['latest'] as Map<String, dynamic>;
      latest['version'] = version;
      latest['build'] = build;
      latest['released_at'] = date;
      if (notes.isNotEmpty) latest['notes'] = notes;
    }

    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(json)}\n');
  }
}
