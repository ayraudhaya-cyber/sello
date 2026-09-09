import 'package:equatable/equatable.dart';

/// Application role — maps role codes to Sello Hub vs Sello Go.
enum UserRole {
  owner,
  manager,
  salesRepresentative,
  storeInCharge,
  salesInCharge;

  /// Hub workspace (Owner, Manager, Store In-charge, Sales In-charge).
  bool get usesHub => this != salesRepresentative;

  /// Field sales experience (Sello Go).
  bool get usesSello => this == salesRepresentative;

  String get label => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.manager => 'Manager',
        UserRole.salesRepresentative => 'Sales Representative',
        UserRole.storeInCharge => 'Store In-charge',
        UserRole.salesInCharge => 'Sales In-charge',
      };

  String get shortLabel => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.manager => 'Manager',
        UserRole.salesRepresentative => 'Sales Rep',
        UserRole.storeInCharge => 'Store In-charge',
        UserRole.salesInCharge => 'Sales In-charge',
      };

  /// Maps `public.roles.code` to [UserRole].
  static UserRole fromCode(String code) {
    switch (code.trim().toLowerCase()) {
      case 'owner':
        return UserRole.owner;
      case 'manager':
        return UserRole.manager;
      case 'sales_representative':
        return UserRole.salesRepresentative;
      case 'store_in_charge':
        return UserRole.storeInCharge;
      case 'sales_in_charge':
        return UserRole.salesInCharge;
      default:
        throw StateError('Unknown role code: $code');
    }
  }
}

/// Navigation destination metadata for breadcrumbs / titles.
class NavMeta extends Equatable {
  const NavMeta({
    required this.title,
    this.parentTitle,
  });

  final String title;
  final String? parentTitle;

  @override
  List<Object?> get props => [title, parentTitle];
}
