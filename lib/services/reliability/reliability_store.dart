import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sello/shared/models/reliability/backup_models.dart';
import 'package:sello/shared/models/reliability/conflict_models.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';

/// Durable local reliability store — outbox, conflicts, backup history.
///
/// SharedPreferences-backed JSON for cross-platform foundation (including web).
/// Can be replaced by Drift later without changing SyncEngine / BackupService APIs.
class ReliabilityStore {
  ReliabilityStore();

  static const _prefsLastSync = 'reliability.last_sync_at';
  static const _prefsLastBackup = 'reliability.last_backup_at';
  static const _prefsSequence = 'reliability.outbox_sequence';
  static const _prefsQueue = 'reliability.sync_outbox';
  static const _prefsConflicts = 'reliability.sync_conflicts';
  static const _prefsBackups = 'reliability.backup_history';
  static const _prefsRestore = 'reliability.restore_session';

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Sync outbox ─────────────────────────────────────────────────────────

  Future<List<SyncQueueItem>> loadQueue() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_prefsQueue);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final row in decoded)
        SyncQueueItem.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<void> saveQueue(List<SyncQueueItem> items) async {
    final prefs = await _preferences;
    await prefs.setString(
      _prefsQueue,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  Future<int> nextSequence() async {
    final prefs = await _preferences;
    final next = (prefs.getInt(_prefsSequence) ?? 0) + 1;
    await prefs.setInt(_prefsSequence, next);
    return next;
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_prefsLastSync);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncAt(DateTime when) async {
    final prefs = await _preferences;
    await prefs.setString(_prefsLastSync, when.toIso8601String());
  }

  // ── Conflicts ───────────────────────────────────────────────────────────

  Future<List<SyncConflict>> loadConflicts() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_prefsConflicts);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final row in decoded)
        SyncConflict.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<void> saveConflicts(List<SyncConflict> items) async {
    final prefs = await _preferences;
    await prefs.setString(
      _prefsConflicts,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  // ── Backups ─────────────────────────────────────────────────────────────

  Future<List<BackupRecord>> loadBackups() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_prefsBackups);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final list = [
      for (final row in decoded)
        BackupRecord.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> saveBackups(List<BackupRecord> items) async {
    final prefs = await _preferences;
    await prefs.setString(
      _prefsBackups,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  Future<DateTime?> lastBackupAt() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_prefsLastBackup);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastBackupAt(DateTime when) async {
    final prefs = await _preferences;
    await prefs.setString(_prefsLastBackup, when.toIso8601String());
  }

  Future<RestoreSession?> loadActiveRestore() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_prefsRestore);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return RestoreSession.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> saveActiveRestore(RestoreSession? session) async {
    final prefs = await _preferences;
    if (session == null) {
      await prefs.remove(_prefsRestore);
      return;
    }
    await prefs.setString(_prefsRestore, jsonEncode(session.toJson()));
  }
}
