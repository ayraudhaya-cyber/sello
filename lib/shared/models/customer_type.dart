enum CustomerType {
  retail,
  wholesale;

  String get label => switch (this) {
        CustomerType.retail => 'Retail',
        CustomerType.wholesale => 'Wholesale',
      };

  String get dbValue => name;

  static CustomerType fromDb(String? value) {
    return switch (value) {
      'wholesale' => CustomerType.wholesale,
      _ => CustomerType.retail,
    };
  }
}
