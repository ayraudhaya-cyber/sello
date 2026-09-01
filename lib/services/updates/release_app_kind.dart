import 'package:sello/shared/models/user_role.dart';

/// Which Sello mobile binary a release entry belongs to.
enum ReleaseAppKind {
  salesRep,
  ownerManager;

  String get jsonKey => switch (this) {
        ReleaseAppKind.salesRep => 'sales_rep',
        ReleaseAppKind.ownerManager => 'owner_manager',
      };

  static ReleaseAppKind? tryParse(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'sales_rep' || 'sales' || 'sello' => ReleaseAppKind.salesRep,
      'owner_manager' || 'owner' || 'hub' => ReleaseAppKind.ownerManager,
      _ => null,
    };
  }

  /// Existing workspace mapping — Sales Rep vs Owner/Manager Hub.
  static ReleaseAppKind fromUserRole(UserRole role) {
    return role.usesSello
        ? ReleaseAppKind.salesRep
        : ReleaseAppKind.ownerManager;
  }
}
