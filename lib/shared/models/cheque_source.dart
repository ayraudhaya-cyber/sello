enum ChequeSource {
  sello,
  existing;

  String get dbValue => switch (this) {
        ChequeSource.sello => 'sello',
        ChequeSource.existing => 'existing',
      };

  static ChequeSource fromDb(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'existing' => ChequeSource.existing,
      _ => ChequeSource.sello,
    };
  }
}
