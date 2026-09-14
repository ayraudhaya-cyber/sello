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
        ChequeStatus.awaitingCollection => 'Awaiting collection',
        ChequeStatus.collected => 'Collected',
        ChequeStatus.deposited => 'Deposited',
        ChequeStatus.cleared => 'Cleared',
        ChequeStatus.bounced => 'Bounced',
        ChequeStatus.cancelled => 'Cancelled',
      };

  /// Default label when financial apply state is unknown.
  String get label => shortLabel;

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
