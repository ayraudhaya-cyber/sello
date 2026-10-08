import 'dart:io';

/// Off during `flutter test`, where path_provider has no implementation.
bool get productImageDiskCacheSupported =>
    !Platform.environment.containsKey('FLUTTER_TEST');
