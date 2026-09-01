/// Lifecycle of a payment ledger row (not order.payment_status).
enum PaymentRecordStatus {
  completed,
  pending,
  refunded,
  cancelled,
  rejected;

  String get label => switch (this) {
    PaymentRecordStatus.completed => 'Completed',
    PaymentRecordStatus.pending => 'Pending Review',
    PaymentRecordStatus.refunded => 'Refunded',
    PaymentRecordStatus.cancelled => 'Cancelled',
    PaymentRecordStatus.rejected => 'Rejected',
  };

  String get dbValue => name;

  bool get isPendingReview => this == PaymentRecordStatus.pending;

  static PaymentRecordStatus fromDb(String? value) {
    return switch (value) {
      'pending' => PaymentRecordStatus.pending,
      'refunded' => PaymentRecordStatus.refunded,
      'cancelled' => PaymentRecordStatus.cancelled,
      'rejected' => PaymentRecordStatus.rejected,
      _ => PaymentRecordStatus.completed,
    };
  }
}
