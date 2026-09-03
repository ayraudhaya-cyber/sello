enum OrderStatus {
  draft,
  /// Demand recorded; fulfillment may be pending or in progress.
  placed,
  /// At least one unit delivered; outstanding remaining quantity.
  partiallyDelivered,
  /// Fulfillment finished (delivered + cancelled cover ordered qty).
  completed,
  cancelled;

  String get label => switch (this) {
        OrderStatus.draft => 'Draft',
        OrderStatus.placed => 'Placed',
        OrderStatus.partiallyDelivered => 'Partially delivered',
        OrderStatus.completed => 'Completed',
        OrderStatus.cancelled => 'Cancelled',
      };

  String get dbValue => switch (this) {
        OrderStatus.partiallyDelivered => 'partially_delivered',
        _ => name,
      };

  /// Open / in-progress statuses (not finished or cancelled).
  bool get isOpen =>
      this == OrderStatus.draft ||
      this == OrderStatus.placed ||
      this == OrderStatus.partiallyDelivered;

  /// Fulfillment may still receive deliveries.
  bool get canFulfill =>
      this == OrderStatus.placed || this == OrderStatus.partiallyDelivered;

  /// Phase 1 primary statuses shown in filters / creation.
  bool get isPrimaryPhase =>
      this == OrderStatus.draft ||
      this == OrderStatus.completed ||
      this == OrderStatus.cancelled;

  static OrderStatus fromDb(String? value) {
    return switch (value) {
      // Legacy unused status — migrated to placed in 054.
      'submitted' => OrderStatus.placed,
      'placed' => OrderStatus.placed,
      'partially_delivered' => OrderStatus.partiallyDelivered,
      'completed' => OrderStatus.completed,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.draft,
    };
  }
}
