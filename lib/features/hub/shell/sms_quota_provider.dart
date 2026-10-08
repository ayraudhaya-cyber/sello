import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/sms_quota.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hub header quota. Hidden when this company has no Text.lk token yet.
final smsQuotaProvider =
    AsyncNotifierProvider<SmsQuotaController, SmsQuotaView>(
      SmsQuotaController.new,
    );

class SmsQuotaController extends AsyncNotifier<SmsQuotaView> {
  static const _refreshAfter = Duration(minutes: 5);

  @override
  Future<SmsQuotaView> build() {
    final timer = Timer(_refreshAfter, () => ref.invalidateSelf());
    ref.onDispose(timer.cancel);
    return _load();
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<SmsQuotaView> _load() async {
    if (!SupabaseService.isInitialized) return const SmsQuotaView.hidden();
    try {
      final response = await SupabaseService.client.functions.invoke(
        'sms-quota',
      );
      return SmsQuotaView.fromEdgeJson(_asMap(response.data));
    } on FunctionException {
      return const SmsQuotaView.unavailable();
    } catch (_) {
      return const SmsQuotaView.unavailable();
    }
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
