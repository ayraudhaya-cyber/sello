import 'package:uuid/uuid.dart';

/// Generates idempotent offline client ids for mutations.
///
/// Aligns with DB columns like `orders.offline_client_id` and
/// `customer_visits.offline_client_id`.
abstract final class OfflineClientIds {
  static const _uuid = Uuid();

  static String create() => _uuid.v4();
}
