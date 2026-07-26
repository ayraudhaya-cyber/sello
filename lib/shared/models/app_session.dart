import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/user_role.dart';

/// Lifecycle of authentication for splash / route guards.
enum AuthStatus {
  /// Cold start — session restore in progress.
  unknown,

  /// No valid session.
  unauthenticated,

  /// Sign-in request in flight.
  authenticating,

  /// Signed in with a resolved role.
  authenticated,
}

/// Lightweight session snapshot shared across shells.
class AppSession extends Equatable {
  const AppSession({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    this.companyName,
    this.avatarUrl,
  });

  final String userId;
  final String email;
  final String displayName;
  final UserRole role;
  final String? companyName;
  final String? avatarUrl;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  List<Object?> get props =>
      [userId, email, displayName, role, companyName, avatarUrl];
}
