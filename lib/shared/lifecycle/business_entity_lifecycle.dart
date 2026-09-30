/// Active / inactive lifecycle for business masters (products, customers,
/// suppliers, team). Transactional rows are not covered here.
abstract final class BusinessEntityLifecycle {
  /// Choices offered when starting a new sale, visit, or assignment.
  static List<T> forNewTransactions<T>(
    Iterable<T> items,
    bool Function(T item) isActive,
  ) {
    return [for (final item in items) if (isActive(item)) item];
  }

  /// Permanent delete is only for records that were never used in business
  /// history. Anything already referenced stays inactive instead.
  static PermanentDeleteDecision permanentDelete({
    required bool isActive,
    required bool hasHistoricalUse,
    required String noun,
  }) {
    if (hasHistoricalUse) {
      return PermanentDeleteDecision.blocked(
        'This $noun is part of business history, so it cannot be deleted. '
        'Deactivate it instead. Existing records keep this $noun.',
      );
    }
    if (isActive) {
      return PermanentDeleteDecision.blocked(
        'Deactivate this $noun before permanently deleting it.',
      );
    }
    return const PermanentDeleteDecision.allowed();
  }
}

class PermanentDeleteDecision {
  const PermanentDeleteDecision.allowed() : message = null;

  const PermanentDeleteDecision.blocked(this.message);

  final String? message;

  bool get allowed => message == null;
}
