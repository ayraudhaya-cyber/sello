import 'package:equatable/equatable.dart';

/// Application role — maps to Sello vs Sello Hub after login.
enum UserRole {
  owner,
  manager,
  salesRepresentative;

  bool get usesHub => this == owner || this == manager;
  bool get usesSello => this == salesRepresentative;

  String get label => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.manager => 'Manager',
        UserRole.salesRepresentative => 'Sales Representative',
      };

  String get shortLabel => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.manager => 'Manager',
        UserRole.salesRepresentative => 'Sales Rep',
      };
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
