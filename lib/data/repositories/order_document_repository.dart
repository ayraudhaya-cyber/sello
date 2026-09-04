import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/notifications/outbound/document_link_factory.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persistence for order confirmation tokens and the public document RPC.
class OrderDocumentRepository {
  OrderDocumentRepository({
    SupabaseClient? client,
    this.links = const DocumentLinkFactory(),
  }) : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;
  final DocumentLinkFactory links;

  Future<OutboundNotificationPolicies> fetchOutboundPolicies() async {
    try {
      final row = await _client
          .from('company_settings')
          .select('outbound_notification_policies')
          .limit(1)
          .maybeSingle();
      return OutboundNotificationPolicies.fromJson(
        row?['outbound_notification_policies'],
      );
    } catch (_) {
      return OutboundNotificationPolicies.defaults;
    }
  }

  /// Ensures a document token exists and returns the public invoice URL.
  /// Independent of WhatsApp/SMS channel switches.
  Future<String> invoiceUrlForOrder(String orderId) async {
    final prepared = await prepareConfirmation(orderId);
    final url = links.orderDocument(prepared.token).trim();
    if (url.isEmpty) {
      throw const ValidationFailure(
        'Invoice link is not available for this order yet.',
      );
    }
    return url;
  }

  Future<OrderConfirmationPrepareResult> prepareConfirmation(
    String orderId,
  ) async {
    try {
      final result = await _client.rpc(
        'prepare_order_confirmation',
        params: {'p_order_id': orderId},
      );
      if (result is Map<String, dynamic>) {
        return OrderConfirmationPrepareResult.fromJson(result);
      }
      if (result is Map) {
        return OrderConfirmationPrepareResult.fromJson(
          Map<String, dynamic>.from(result),
        );
      }
      throw const UnexpectedFailure('Unable to prepare order confirmation.');
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to prepare order confirmation.'
            : error.message,
      );
    }
  }

  Future<CollectionAcknowledgementPrepareResult>
      prepareCollectionAcknowledgement(String paymentId) async {
    try {
      final result = await _client.rpc(
        'prepare_collection_acknowledgement',
        params: {'p_payment_id': paymentId},
      );
      if (result is Map<String, dynamic>) {
        return CollectionAcknowledgementPrepareResult.fromJson(result);
      }
      if (result is Map) {
        return CollectionAcknowledgementPrepareResult.fromJson(
          Map<String, dynamic>.from(result),
        );
      }
      throw const UnexpectedFailure(
        'Unable to prepare collection acknowledgement.',
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to prepare collection acknowledgement.'
            : error.message,
      );
    }
  }

  Future<bool> recordDispatch({
    required String eventId,
    required OutboundChannel channel,
    required OutboundRecipientKind recipientKind,
    required String recipientKey,
    String? address,
    OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
    String? skipReason,
  }) async {
    try {
      final result = await _client.rpc(
        'record_outbound_dispatch',
        params: {
          'p_event_id': eventId,
          'p_channel': channel.dbValue,
          'p_recipient_kind': recipientKind.dbValue,
          'p_recipient_key': recipientKey,
          'p_address': address,
          'p_status': status.dbValue,
          'p_skip_reason': skipReason,
          'p_payload': <String, dynamic>{},
        },
      );
      return result == true;
    } on PostgrestException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Public resolve — works with anon key, no session.
  Future<OrderDocument?> fetchByToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.length < 32) return null;
    try {
      dynamic result;
      try {
        result = await _client.rpc(
          'get_public_document_by_token',
          params: {'p_token': trimmed},
        );
      } catch (_) {
        result = null;
      }
      result ??= await _client.rpc(
        'get_order_document_by_token',
        params: {'p_token': trimmed},
      );
      if (result == null) return null;
      if (result is Map<String, dynamic>) {
        return OrderDocument.fromJson(result);
      }
      if (result is Map) {
        return OrderDocument.fromJson(Map<String, dynamic>.from(result));
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
