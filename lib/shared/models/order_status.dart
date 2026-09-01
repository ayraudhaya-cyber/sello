enum OrderStatus {
  draft,
  submitted,
  completed,
  cancelled;

  String get label => switch (this) {
        OrderStatus.draft => 'Draft',
        OrderStatus.submitted => 'Processing',
        OrderStatus.completed => 'Completed',
        OrderStatus.cancelled => 'Cancelled',
      };

  String get dbValue => name;

  /// Phase 1 primary statuses shown in filters / creation.
  bool get isPrimaryPhase =>
      this == OrderStatus.draft ||
      this == OrderStatus.completed ||
      this == OrderStatus.cancelled;

  static OrderStatus fromDb(String? value) {
    return switch (value) {
      'submitted' => OrderStatus.submitted,
      'completed' => OrderStatus.completed,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.draft,
    };
  }
}
