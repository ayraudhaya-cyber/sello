enum ChequeStatus {
  awaitingCollection,
  collected,
  deposited,
  cleared,
  bounced,
  cancelled;

  String get dbValue => switch (this) {
    ChequeStatus.awaitingCollection => 'awaiting_collection',
    ChequeStatus.collected => 'collected',
    ChequeStatus.deposited => 'deposited',
    ChequeStatus.cleared => 'cleared',
    ChequeStatus.bounced => 'bounced',
    ChequeStatus.cancelled => 'cancelled',
  };

  String get shortLabel => switch (this) {
    ChequeStatus.awaitingCollection => 'Waiting to receive',
    ChequeStatus.collected => 'In hand',
    ChequeStatus.deposited => 'At the bank',
    ChequeStatus.cleared => 'Bank paid',
    ChequeStatus.bounced => 'Bank returned',
    ChequeStatus.cancelled => 'Cancelled',
  };

  /// Default label when financial apply state is unknown.
  String get label => shortLabel;

  /// When this status applies — shown on hover for chips and badges.
  String get helpText => switch (this) {
    ChequeStatus.awaitingCollection =>
      'The customer has not given you this cheque yet.',
    ChequeStatus.collected => 'You have the cheque. It is not at the bank yet.',
    ChequeStatus.deposited =>
      'The cheque is at your bank. Waiting for the bank to pay it.',
    ChequeStatus.cleared => 'The bank paid this cheque. The money is in.',
    ChequeStatus.bounced => 'The bank sent this cheque back unpaid.',
    ChequeStatus.cancelled => 'This cheque will not be used.',
  };

  bool get canCollect => this == ChequeStatus.awaitingCollection;

  bool get canClear => this == ChequeStatus.deposited;

  bool get canCancel =>
      this == ChequeStatus.awaitingCollection ||
      this == ChequeStatus.collected ||
      this == ChequeStatus.deposited ||
      this == ChequeStatus.cleared;

  static ChequeStatus? fromDb(String? value) {
    return switch (value) {
      'awaiting_collection' => ChequeStatus.awaitingCollection,
      'collected' => ChequeStatus.collected,
      'deposited' => ChequeStatus.deposited,
      'cleared' => ChequeStatus.cleared,
      'bounced' => ChequeStatus.bounced,
      'cancelled' => ChequeStatus.cancelled,
      _ => null,
    };
  }
}
