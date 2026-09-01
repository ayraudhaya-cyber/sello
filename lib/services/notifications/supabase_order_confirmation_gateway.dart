import 'package:sello/data/repositories/order_document_repository.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/shared/models/order_document.dart';

class SupabaseOrderConfirmationGateway implements OrderConfirmationGateway {
  SupabaseOrderConfirmationGateway(this._documents);

  final OrderDocumentRepository _documents;

  @override
  Future<OrderConfirmationPrepareResult> prepare(String orderId) =>
      _documents.prepareConfirmation(orderId);

  @override
  Future<bool> recordDispatch({
    required String eventId,
    required OutboundChannel channel,
    required OutboundRecipientKind recipientKind,
    required String recipientKey,
    String? address,
    OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
    String? skipReason,
  }) {
    return _documents.recordDispatch(
      eventId: eventId,
      channel: channel,
      recipientKind: recipientKind,
      recipientKey: recipientKey,
      address: address,
      status: status,
      skipReason: skipReason,
    );
  }
}
