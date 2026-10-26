import 'dart:async';

import 'package:sello/core/error/app_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How a profile load failed, without treating every server error as rejection.
abstract final class SessionProfileFailure {
  /// The device or Supabase could not be reached.
  static bool isTransport(Object error) {
    if (error is NetworkFailure || error is OfflineFailure) return true;
    if (error is TimeoutException) return true;
    if (error is AuthRetryableFetchException) return true;
    if (error is PostgrestException) return _postgrestTransport(error);
    return _textLooksLikeTransport(error.runtimeType.toString()) ||
        _textLooksLikeTransport(error.toString());
  }

  /// The server answered, but not with a confirmed inactive account.
  ///
  /// An expired JWT is not proof the employee was disabled.
  static bool isUnconfirmed(Object error) {
    if (error is! PostgrestException) return false;
    if (_postgrestTransport(error)) return false;
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    return code == 'pgrst301' ||
        code == '401' ||
        message.contains('jwt') ||
        message.contains('invalid claim');
  }

  /// Cached workspace metadata may be shown. It is not a fresh authorization.
  static bool canUseCachedProfile(Object error) =>
      isTransport(error) || isUnconfirmed(error);

  static bool _postgrestTransport(PostgrestException error) {
    final code = (error.code ?? '').toLowerCase();
    if (code == '408' ||
        code == '502' ||
        code == '503' ||
        code == '504' ||
        code == '08000' ||
        code == '08006' ||
        code == '57p01' ||
        code == '53300') {
      return true;
    }
    return _textLooksLikeTransport(error.message);
  }

  static bool _textLooksLikeTransport(String raw) {
    final text = raw.toLowerCase();
    const needles = [
      'socketexception',
      'failed host lookup',
      'network is unreachable',
      'connection refused',
      'connection reset',
      'connection aborted',
      'connection timed out',
      'timed out',
      'timeout',
      'failed to fetch',
      'xmlhttprequest',
      'clientexception',
      'network error',
      'software caused connection abort',
      'temporarily unavailable',
      'service unavailable',
      'bad gateway',
      'gateway timeout',
    ];
    return needles.any(text.contains);
  }
}
