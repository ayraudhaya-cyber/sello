import 'dart:convert';

import 'package:sello/services/orders/visit_order_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences draft for an in-progress Sales Rep visit order.
///
/// Scoped to company + employee — never crosses tenants or users.
class VisitOrderDraftStore {
  VisitOrderDraftStore();

  static const _keyPrefix = 'visit_order_draft.';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _key(String companyId, String employeeId) =>
      '$_keyPrefix$companyId.$employeeId';

  Future<VisitOrderDraft?> load({
    required String companyId,
    required String employeeId,
  }) async {
    final prefs = await _preferences;
    final raw = prefs.getString(_key(companyId, employeeId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final draft = VisitOrderDraft.fromJson(Map<String, dynamic>.from(decoded));
      if (draft.companyId != companyId || draft.employeeId != employeeId) {
        return null;
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(VisitOrderDraft draft) async {
    final prefs = await _preferences;
    await prefs.setString(
      _key(draft.companyId, draft.employeeId),
      jsonEncode(draft.toJson()),
    );
  }

  Future<void> clear({
    required String companyId,
    required String employeeId,
  }) async {
    final prefs = await _preferences;
    await prefs.remove(_key(companyId, employeeId));
  }
}
