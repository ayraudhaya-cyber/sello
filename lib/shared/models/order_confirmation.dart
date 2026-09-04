import 'package:equatable/equatable.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';

/// Result of preparing order confirmation after a successful complete.
class OrderConfirmationOutcome extends Equatable {
  const OrderConfirmationOutcome({
    required this.orderNumber,
    required this.documentUrl,
    required this.messageBody,
    required this.alreadyPrepared,
    this.eventId,
    this.token,
    this.actions = const [],
    this.customerSkippedReason,
    this.includeDocumentLink = true,
  });

  final String orderNumber;
  final String documentUrl;
  final String messageBody;
  final bool alreadyPrepared;
  final String? eventId;
  final String? token;
  final List<OrderConfirmationAction> actions;
  final String? customerSkippedReason;

  /// Whether the tenant message template includes the document link.
  /// [documentUrl] is still set so View invoice can open the page.
  final bool includeDocumentLink;

  static const empty = OrderConfirmationOutcome(
    orderNumber: '',
    documentUrl: '',
    messageBody: '',
    alreadyPrepared: false,
  );

  bool get hasShareActions => actions.isNotEmpty;

  bool get customerWasSkipped =>
      customerSkippedReason != null && customerSkippedReason!.isNotEmpty;

  List<OrderConfirmationAction> get customerActions =>
      actions.where((a) => a.recipientKind == OutboundRecipientKind.customer).toList();

  List<OrderConfirmationAction> get hubActions =>
      actions.where((a) => a.recipientKind == OutboundRecipientKind.hub).toList();

  List<OrderConfirmationAction> get salesRepActions =>
      actions
          .where((a) => a.recipientKind == OutboundRecipientKind.salesRep)
          .toList();

  @override
  List<Object?> get props => [
        orderNumber,
        documentUrl,
        alreadyPrepared,
        eventId,
        token,
        actions,
        customerSkippedReason,
        includeDocumentLink,
      ];
}

class OrderConfirmationAction extends Equatable {
  const OrderConfirmationAction({
    required this.channel,
    required this.recipientKind,
    required this.recipientKey,
    required this.label,
    required this.launchUri,
    this.recipientName,
    this.address,
    this.duplicate = false,
  });

  final OutboundChannel channel;
  final OutboundRecipientKind recipientKind;
  final String recipientKey;
  final String label;
  final String launchUri;
  final String? recipientName;
  final String? address;
  final bool duplicate;

  @override
  List<Object?> get props => [
        channel,
        recipientKind,
        recipientKey,
        launchUri,
        duplicate,
      ];
}

/// Return value for Hub / Sales order writes.
class OrderMutationResult {
  const OrderMutationResult.ok({this.confirmation}) : error = null;

  const OrderMutationResult.fail(this.error) : confirmation = null;

  final String? error;
  final OrderConfirmationOutcome? confirmation;

  bool get isOk => error == null;
}
