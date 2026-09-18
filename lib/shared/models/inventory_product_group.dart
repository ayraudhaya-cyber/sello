import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/stock_movement_type.dart';

/// Parent-grouped inventory rows for Hub Inventory (client-side only).
class InventoryProductGroup {
  const InventoryProductGroup({
    required this.productId,
    required this.items,
  });

  final String productId;
  final List<InventoryItem> items;

  InventoryItem get primary => items.first;

  /// More than one inventory row for the same parent → expandable options.
  bool get isMultiOption => items.length > 1;

  num get totalQuantity =>
      items.fold<num>(0, (sum, item) => sum + item.quantity);

  num get totalAvailableQuantity =>
      items.fold<num>(0, (sum, item) => sum + item.availableQuantity);

  num? get reorderLevel {
    num? value;
    for (final item in items) {
      if (item.reorderLevel == null) continue;
      value = (value ?? 0) + item.reorderLevel!;
    }
    return value;
  }

  DateTime? get lastMovementAt {
    DateTime? latest;
    for (final item in items) {
      final at = item.lastMovementAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  StockStatus get stockStatus {
    if (!primary.isActive) return StockStatus.archived;
    if (totalQuantity <= 0) return StockStatus.out;
    final reorder = reorderLevel;
    if (reorder != null && totalQuantity <= reorder) return StockStatus.low;
    return StockStatus.healthy;
  }
}

/// Groups flat variant inventory rows by [InventoryItem.productId].
///
/// Preserves first-seen product order from [items] (already sorted by the
/// repository). Within a group, default/unlabeled options stay first.
List<InventoryProductGroup> groupInventoryItems(List<InventoryItem> items) {
  final order = <String>[];
  final buckets = <String, List<InventoryItem>>{};
  for (final item in items) {
    final list = buckets.putIfAbsent(item.productId, () {
      order.add(item.productId);
      return <InventoryItem>[];
    });
    list.add(item);
  }

  return [
    for (final productId in order)
      InventoryProductGroup(
        productId: productId,
        items: _sortOptionRows(buckets[productId]!),
      ),
  ];
}

List<InventoryItem> _sortOptionRows(List<InventoryItem> rows) {
  final copy = List<InventoryItem>.from(rows);
  copy.sort((a, b) {
    final aLabel = a.variantLabel?.trim() ?? '';
    final bLabel = b.variantLabel?.trim() ?? '';
    final aSimple = aLabel.isEmpty;
    final bSimple = bLabel.isEmpty;
    if (aSimple != bSimple) return aSimple ? -1 : 1;
    final labelCmp = aLabel.compareTo(bLabel);
    if (labelCmp != 0) return labelCmp;
    return (a.variantSku ?? a.sku).compareTo(b.variantSku ?? b.sku);
  });
  return copy;
}

/// Shared last-active guard for editor / repository callers.
String? validateLastActiveOption({
  required int activeCountAfterChange,
}) {
  if (activeCountAfterChange < 1) {
    return 'Keep at least one active sellable option.';
  }
  return null;
}
