import 'dart:convert';

import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls the `send-outbound-sms` Edge Function. Text.lk token stays server-side.
class SupabaseOutboundSmsSender implements OutboundSmsSender {
  SupabaseOutboundSmsSender({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const functionName = 'send-outbound-sms';

  @override
  Future<OutboundSmsResult> send(OutboundSmsRequest request) async {
    return _invoke(request.toJson());
  }

  @override
  Future<OutboundSmsResult> sendTest({required String recipient}) async {
    return _invoke(OutboundSmsTest.requestJson(recipient));
  }

  @override
  Future<OutboundSmsResult> verifySender({
    required String recipient,
    required String senderId,
  }) async {
    return _invoke(
      OutboundSmsVerify.requestJson(recipient: recipient, senderId: senderId),
    );
  }

  Future<OutboundSmsResult> _invoke(Map<String, String> body) async {
    try {
      final response = await _client.functions.invoke(
        functionName,
        body: body,
      );
      final data = _asMap(response.data);
      if (data != null) {
        final status = data['status']?.toString();
        final reason = data['reason']?.toString();
        final activated = data.containsKey('activated')
            ? data['activated'] == true
            : null;
        if (reason == 'missing_sender_id') {
          return OutboundSmsResult(
            OutboundSmsStatus.skippedMissingSender,
            reason: reason,
          );
        }
        return OutboundSmsResult(
          outboundSmsStatusFromJson(status),
          reason: reason,
          activated: activated,
        );
      }
      return const OutboundSmsResult(
        OutboundSmsStatus.failed,
        reason: 'invalid_request',
      );
    } catch (_) {
      return const OutboundSmsResult(
        OutboundSmsStatus.failed,
        reason: 'network',
      );
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
      } catch (_) {}
    }
    return null;
  }
}
