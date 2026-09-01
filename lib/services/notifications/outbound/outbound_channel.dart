/// Outbound delivery channels for business notifications.
///
/// WhatsApp is a device prefill (`wa.me`). SMS is sent server-side via Text.lk.
enum OutboundChannel {
  whatsapp,
  sms,
  inApp;

  String get dbValue => switch (this) {
        OutboundChannel.whatsapp => 'whatsapp',
        OutboundChannel.sms => 'sms',
        OutboundChannel.inApp => 'in_app',
      };
}

/// Which outbound channels are active for a company (master switches).
class OutboundChannelPolicy {
  const OutboundChannelPolicy({
    this.whatsapp = true,
    this.sms = true,
    this.inAppHub = true,
  });

  final bool whatsapp;
  final bool sms;
  final bool inAppHub;

  /// Legacy Phase 1 defaults — prefer company [OutboundNotificationPolicies].
  static const phase1 = OutboundChannelPolicy();

  factory OutboundChannelPolicy.fromType({
    required bool masterWhatsapp,
    required bool masterSms,
    required bool typeWhatsapp,
    required bool typeSms,
  }) {
    return OutboundChannelPolicy(
      whatsapp: masterWhatsapp && typeWhatsapp,
      sms: masterSms && typeSms,
    );
  }

  bool isEnabled(OutboundChannel channel) => switch (channel) {
        OutboundChannel.whatsapp => whatsapp,
        OutboundChannel.sms => sms,
        OutboundChannel.inApp => inAppHub,
      };
}

enum OutboundRecipientKind {
  customer,
  hub,
  salesRep;

  String get dbValue => switch (this) {
        OutboundRecipientKind.customer => 'customer',
        OutboundRecipientKind.hub => 'hub',
        OutboundRecipientKind.salesRep => 'sales_rep',
      };
}

enum OutboundDispatchStatus {
  prepared,
  skipped,
  failed,
  sent;

  String get dbValue => name;
}
