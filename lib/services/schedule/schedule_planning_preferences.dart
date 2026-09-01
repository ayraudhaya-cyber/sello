import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight Schedule planning context — preferences only, never a visit list.
///
/// Remembers last/recent rep and area so managers can plan tomorrow faster.
/// Does **not** store or recreate customer stops.
class SchedulePlanningPreferences {
  const SchedulePlanningPreferences({
    this.lastEmployeeId,
    this.lastEmployeeName,
    this.lastArea,
    this.recentEmployeeIds = const [],
    this.recentAreas = const [],
  });

  final String? lastEmployeeId;
  final String? lastEmployeeName;
  final String? lastArea;
  final List<String> recentEmployeeIds;
  final List<String> recentAreas;

  static const empty = SchedulePlanningPreferences();

  bool get hasRecentRep =>
      lastEmployeeId != null && lastEmployeeId!.trim().isNotEmpty;

  bool get hasRecentArea => lastArea != null && lastArea!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'lastEmployeeId': lastEmployeeId,
        'lastEmployeeName': lastEmployeeName,
        'lastArea': lastArea,
        'recentEmployeeIds': recentEmployeeIds,
        'recentAreas': recentAreas,
      };

  factory SchedulePlanningPreferences.fromJson(Map<String, dynamic> json) {
    return SchedulePlanningPreferences(
      lastEmployeeId: json['lastEmployeeId'] as String?,
      lastEmployeeName: json['lastEmployeeName'] as String?,
      lastArea: json['lastArea'] as String?,
      recentEmployeeIds: _stringList(json['recentEmployeeIds']),
      recentAreas: _stringList(json['recentAreas']),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }
}

/// Persists [SchedulePlanningPreferences] per company workspace.
class SchedulePlanningPreferencesStore {
  SchedulePlanningPreferencesStore();

  static const _keyPrefix = 'schedule.planning_prefs.';
  static const _maxRecent = 5;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _key(String companyId) => '$_keyPrefix$companyId';

  Future<SchedulePlanningPreferences> load(String companyId) async {
    final prefs = await _preferences;
    final raw = prefs.getString(_key(companyId));
    if (raw == null || raw.isEmpty) return SchedulePlanningPreferences.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return SchedulePlanningPreferences.empty;
      return SchedulePlanningPreferences.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return SchedulePlanningPreferences.empty;
    }
  }

  Future<void> rememberPlan({
    required String companyId,
    String? employeeId,
    String? employeeName,
    String? area,
  }) async {
    final current = await load(companyId);
    final nextAreas = _pushUnique(
      current.recentAreas,
      area?.trim(),
    );
    final nextReps = _pushUnique(
      current.recentEmployeeIds,
      employeeId?.trim(),
    );

    final next = SchedulePlanningPreferences(
      lastEmployeeId: employeeId?.trim().isNotEmpty == true
          ? employeeId!.trim()
          : current.lastEmployeeId,
      lastEmployeeName: employeeName?.trim().isNotEmpty == true
          ? employeeName!.trim()
          : current.lastEmployeeName,
      lastArea: area?.trim().isNotEmpty == true
          ? area!.trim()
          : current.lastArea,
      recentEmployeeIds: nextReps,
      recentAreas: nextAreas,
    );

    final prefs = await _preferences;
    await prefs.setString(_key(companyId), jsonEncode(next.toJson()));
  }

  List<String> _pushUnique(List<String> existing, String? value) {
    if (value == null || value.isEmpty) return existing;
    final out = <String>[value];
    for (final item in existing) {
      if (item.toLowerCase() == value.toLowerCase()) continue;
      out.add(item);
      if (out.length >= _maxRecent) break;
    }
    return out;
  }
}
