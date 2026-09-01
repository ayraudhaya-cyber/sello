import 'package:sello/services/reliability/sync_outbox.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';

/// Shared integrity checks for the reliability layer.
///
/// Ensures no duplicate open sync rows and safe retry behaviour.
class IntegrityGuard {
  IntegrityGuard({required SyncOutbox outbox}) : _outbox = outbox;

  final SyncOutbox _outbox;

  /// Validate outbox invariants. Returns human-friendly issues (empty = OK).
  Future<List<String>> validateOutbox() async {
    final items = await _outbox.all();
    final issues = <String>[];

    final openByClient = <String, int>{};
    for (final item in items) {
      if (!item.status.isOpen) continue;
      openByClient[item.clientId] = (openByClient[item.clientId] ?? 0) + 1;
    }
    for (final entry in openByClient.entries) {
      if (entry.value > 1) {
        issues.add(
          'Duplicate pending sync for the same change (${entry.key}).',
        );
      }
    }

    final inFlight = items.where((i) => i.status == SyncItemStatus.inFlight);
    if (inFlight.length > 1) {
      issues.add('Multiple sync items are marked in-flight at once.');
    }

    return issues;
  }

  /// Collapse duplicate open rows keeping the earliest sequence.
  Future<int> dedupeOpenItems() async {
    final items = await _outbox.all();
    final seen = <String>{};
    final kept = <SyncQueueItem>[];
    var removed = 0;

    final sorted = [...items]
      ..sort((a, b) {
        final as = a.sequence ?? 0;
        final bs = b.sequence ?? 0;
        return as.compareTo(bs);
      });

    for (final item in sorted) {
      if (item.status.isOpen) {
        if (seen.contains(item.clientId)) {
          removed++;
          continue;
        }
        seen.add(item.clientId);
      }
      kept.add(item);
    }

    if (removed > 0) {
      await _outbox.replaceAll(kept);
    }
    return removed;
  }
}
