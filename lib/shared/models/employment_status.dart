/// Employment lifecycle for `public.employees.employment_status`.
enum EmploymentStatus {
  active,
  inactive,
  suspended,
  archived;

  String get code => name;

  String get label => switch (this) {
        EmploymentStatus.active => 'Active',
        EmploymentStatus.inactive => 'Inactive',
        EmploymentStatus.suspended => 'Suspended',
        EmploymentStatus.archived => 'Archived',
      };

  /// Archived / suspended / inactive cannot authenticate.
  bool get canAuthenticate => this == EmploymentStatus.active;

  static EmploymentStatus fromCode(String? code) {
    switch ((code ?? 'active').trim().toLowerCase()) {
      case 'inactive':
        return EmploymentStatus.inactive;
      case 'suspended':
        return EmploymentStatus.suspended;
      case 'archived':
        return EmploymentStatus.archived;
      case 'active':
      default:
        return EmploymentStatus.active;
    }
  }
}
