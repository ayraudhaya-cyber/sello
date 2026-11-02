/// When inventory quantity is reduced for a sale.
///
/// Stored company preference. Open orders reserve stock when they are placed,
/// and on-hand quantity drops when delivery is recorded. This value is not a
/// live switch.
enum InventoryMovementPolicy {
  /// Hold stock when the order is saved (draft or confirmed).
  reserveOnOrder,

  /// Reduce stock when an owner/manager approves the order.
  deductOnApproval,

  /// Reduce stock when the order is completed / invoiced (current default).
  deductOnInvoice,

  /// Reduce stock when goods leave the warehouse.
  deductOnDispatch;

  String get dbValue => switch (this) {
        InventoryMovementPolicy.reserveOnOrder => 'reserve_on_order',
        InventoryMovementPolicy.deductOnApproval => 'deduct_on_approval',
        InventoryMovementPolicy.deductOnInvoice => 'deduct_on_invoice',
        InventoryMovementPolicy.deductOnDispatch => 'deduct_on_dispatch',
      };

  String get label => switch (this) {
        InventoryMovementPolicy.reserveOnOrder => 'Reserve on order',
        InventoryMovementPolicy.deductOnApproval => 'Deduct on approval',
        InventoryMovementPolicy.deductOnInvoice => 'Deduct on invoice',
        InventoryMovementPolicy.deductOnDispatch => 'Deduct on dispatch',
      };

  String get description => switch (this) {
        InventoryMovementPolicy.reserveOnOrder =>
          'Hold stock as soon as the sales rep saves the order.',
        InventoryMovementPolicy.deductOnApproval =>
          'Reduce stock when someone approves the order.',
        InventoryMovementPolicy.deductOnInvoice =>
          'On-hand stock drops when delivery is recorded. Open orders hold available stock from the moment they are placed.',
        InventoryMovementPolicy.deductOnDispatch =>
          'Reduce stock when goods are dispatched from the warehouse.',
      };

  static InventoryMovementPolicy fromDb(String? value) {
    return switch (value) {
      'reserve_on_order' => InventoryMovementPolicy.reserveOnOrder,
      'deduct_on_approval' => InventoryMovementPolicy.deductOnApproval,
      'deduct_on_dispatch' => InventoryMovementPolicy.deductOnDispatch,
      _ => InventoryMovementPolicy.deductOnInvoice,
    };
  }
}
