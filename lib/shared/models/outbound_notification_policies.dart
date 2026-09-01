import 'package:equatable/equatable.dart';

/// Outbound notification categories businesses can configure.
enum OutboundNotificationType {
  orderConfirmation,
  orderNotification,
  collectionAcknowledgement,
  collectionSubmitted,
  invoice,
  receipt;

  String get dbKey => switch (this) {
        OutboundNotificationType.orderConfirmation => 'order_confirmation',
        OutboundNotificationType.orderNotification => 'new_order_notification',
        OutboundNotificationType.collectionAcknowledgement =>
          'collection_acknowledgement',
        OutboundNotificationType.collectionSubmitted => 'collection_submitted',
        OutboundNotificationType.invoice => 'invoice',
        OutboundNotificationType.receipt => 'receipt',
      };

  String get label => switch (this) {
        OutboundNotificationType.orderConfirmation => 'Order confirmation',
        OutboundNotificationType.orderNotification => 'New order',
        OutboundNotificationType.collectionAcknowledgement =>
          'Collection acknowledgement',
        OutboundNotificationType.collectionSubmitted => 'Collection submitted',
        OutboundNotificationType.invoice => 'Invoices',
        OutboundNotificationType.receipt => 'Receipts',
      };

  String get audienceLabel => switch (this) {
        OutboundNotificationType.orderConfirmation => 'Buyer',
        OutboundNotificationType.orderNotification => 'Owner / Manager',
        OutboundNotificationType.collectionAcknowledgement => 'Buyer',
        OutboundNotificationType.collectionSubmitted => 'Owner / Manager',
        OutboundNotificationType.invoice => 'Buyer',
        OutboundNotificationType.receipt => 'Buyer',
      };

  String get hint => switch (this) {
        OutboundNotificationType.orderConfirmation =>
          'Sent to the buyer when an order is completed. Keep it short — the invoice link opens the full item list.',
        OutboundNotificationType.orderNotification =>
          'Sent to the configured Owner / Manager when a new order is completed.',
        OutboundNotificationType.collectionAcknowledgement =>
          'Confirms a collection was recorded for the store. Balances do not change until an Owner / Manager approves.',
        OutboundNotificationType.collectionSubmitted =>
          'Tells the Owner / Manager that a Sales Rep submitted a collection for review.',
        OutboundNotificationType.invoice =>
          'Customer invoice messaging. Enable when you are ready to send invoices separately.',
        OutboundNotificationType.receipt =>
          'Payment receipt messaging after a collection is posted.',
      };

  bool get isOrderFamily => switch (this) {
        OutboundNotificationType.orderConfirmation ||
        OutboundNotificationType.orderNotification ||
        OutboundNotificationType.invoice =>
          true,
        _ => false,
      };

  bool get isCollectionFamily => !isOrderFamily;

  static OutboundNotificationType? tryParse(String? key) {
    return switch (key) {
      'order_confirmation' => OutboundNotificationType.orderConfirmation,
      'new_order_notification' => OutboundNotificationType.orderNotification,
      'collection_acknowledgement' =>
        OutboundNotificationType.collectionAcknowledgement,
      'collection_submitted' => OutboundNotificationType.collectionSubmitted,
      'invoice' => OutboundNotificationType.invoice,
      'receipt' => OutboundNotificationType.receipt,
      _ => null,
    };
  }

  /// V1 Settings editors — invoice/receipt stay in the model for later.
  static const List<OutboundNotificationType> settingsOrder = [
    OutboundNotificationType.orderConfirmation,
    OutboundNotificationType.orderNotification,
    OutboundNotificationType.collectionAcknowledgement,
    OutboundNotificationType.collectionSubmitted,
  ];
}

/// Who may receive an outbound notification for a type.
enum OutboundRecipientTarget {
  customer,
  hub,
  salesRep;

  String get dbKey => switch (this) {
        OutboundRecipientTarget.customer => 'customer',
        OutboundRecipientTarget.hub => 'hub',
        OutboundRecipientTarget.salesRep => 'sales_rep',
      };

  String get label => switch (this) {
        OutboundRecipientTarget.customer => 'Buyer / customer',
        OutboundRecipientTarget.hub => 'Owner / Manager',
        OutboundRecipientTarget.salesRep => 'Sales representative',
      };

  static OutboundRecipientTarget? tryParse(String? key) {
    return switch (key) {
      'customer' => OutboundRecipientTarget.customer,
      'hub' => OutboundRecipientTarget.hub,
      'sales_rep' => OutboundRecipientTarget.salesRep,
      _ => null,
    };
  }
}

/// Per-type channel / recipient / document-link settings.
class OutboundTypePolicy extends Equatable {
  const OutboundTypePolicy({
    required this.enabled,
    required this.whatsapp,
    required this.sms,
    required this.includeDocumentLink,
    required this.recipients,
  });

  final bool enabled;
  final bool whatsapp;
  final bool sms;
  final bool includeDocumentLink;
  final List<OutboundRecipientTarget> recipients;

  bool get hasAnyChannel => whatsapp || sms;

  bool sendsTo(OutboundRecipientTarget target) => recipients.contains(target);

  OutboundTypePolicy copyWith({
    bool? enabled,
    bool? whatsapp,
    bool? sms,
    bool? includeDocumentLink,
    List<OutboundRecipientTarget>? recipients,
  }) {
    return OutboundTypePolicy(
      enabled: enabled ?? this.enabled,
      whatsapp: whatsapp ?? this.whatsapp,
      sms: sms ?? this.sms,
      includeDocumentLink: includeDocumentLink ?? this.includeDocumentLink,
      recipients: recipients ?? this.recipients,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'whatsapp': whatsapp,
        'sms': sms,
        'include_document_link': includeDocumentLink,
        'recipients': [for (final r in recipients) r.dbKey],
      };

  factory OutboundTypePolicy.fromJson(
    Map<String, dynamic>? json, {
    required OutboundTypePolicy fallback,
  }) {
    if (json == null) return fallback;
    final rawRecipients = json['recipients'];
    final parsed = <OutboundRecipientTarget>[];
    if (rawRecipients is List) {
      for (final item in rawRecipients) {
        final target = OutboundRecipientTarget.tryParse(item?.toString());
        if (target != null && !parsed.contains(target)) parsed.add(target);
      }
    }
    return OutboundTypePolicy(
      enabled: json['enabled'] as bool? ?? fallback.enabled,
      whatsapp: json['whatsapp'] as bool? ?? fallback.whatsapp,
      sms: json['sms'] as bool? ?? fallback.sms,
      includeDocumentLink:
          json['include_document_link'] as bool? ?? fallback.includeDocumentLink,
      recipients: parsed.isEmpty ? fallback.recipients : parsed,
    );
  }

  @override
  List<Object?> get props =>
      [enabled, whatsapp, sms, includeDocumentLink, recipients];
}

/// Tenant-wide outbound messaging configuration.
class OutboundNotificationPolicies extends Equatable {
  const OutboundNotificationPolicies({
    required this.whatsappEnabled,
    required this.smsEnabled,
    required this.types,
    this.templates = const {},
  });

  final bool whatsappEnabled;
  final bool smsEnabled;
  final Map<OutboundNotificationType, OutboundTypePolicy> types;

  /// Optional template overrides keyed by [OutboundNotificationType.dbKey].
  final Map<String, String> templates;

  static const defaults = OutboundNotificationPolicies(
    whatsappEnabled: true,
    smsEnabled: true,
    types: {
      OutboundNotificationType.orderConfirmation: OutboundTypePolicy(
        enabled: true,
        whatsapp: true,
        sms: true,
        includeDocumentLink: true,
        recipients: [OutboundRecipientTarget.customer],
      ),
      OutboundNotificationType.orderNotification: OutboundTypePolicy(
        enabled: true,
        whatsapp: true,
        sms: true,
        includeDocumentLink: true,
        recipients: [OutboundRecipientTarget.hub],
      ),
      OutboundNotificationType.collectionAcknowledgement: OutboundTypePolicy(
        enabled: true,
        whatsapp: true,
        sms: true,
        includeDocumentLink: true,
        recipients: [OutboundRecipientTarget.customer],
      ),
      OutboundNotificationType.collectionSubmitted: OutboundTypePolicy(
        enabled: true,
        whatsapp: true,
        sms: true,
        includeDocumentLink: true,
        recipients: [OutboundRecipientTarget.hub],
      ),
      OutboundNotificationType.invoice: OutboundTypePolicy(
        enabled: false,
        whatsapp: true,
        sms: true,
        includeDocumentLink: true,
        recipients: [OutboundRecipientTarget.customer],
      ),
      OutboundNotificationType.receipt: OutboundTypePolicy(
        enabled: false,
        whatsapp: true,
        sms: true,
        includeDocumentLink: true,
        recipients: [OutboundRecipientTarget.customer],
      ),
    },
  );

  OutboundTypePolicy policyFor(OutboundNotificationType type) =>
      types[type] ?? defaults.types[type]!;

  /// Effective channels for a type (company master switch × type flags).
  bool channelWhatsapp(OutboundNotificationType type) =>
      whatsappEnabled && policyFor(type).whatsapp;

  bool channelSms(OutboundNotificationType type) =>
      smsEnabled && policyFor(type).sms;

  bool isActive(OutboundNotificationType type) {
    final policy = policyFor(type);
    return policy.enabled && (channelWhatsapp(type) || channelSms(type));
  }

  String? templateOverride(OutboundNotificationType type) {
    final text = templates[type.dbKey]?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  OutboundNotificationPolicies copyWith({
    bool? whatsappEnabled,
    bool? smsEnabled,
    Map<OutboundNotificationType, OutboundTypePolicy>? types,
    Map<String, String>? templates,
  }) {
    return OutboundNotificationPolicies(
      whatsappEnabled: whatsappEnabled ?? this.whatsappEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      types: types ?? this.types,
      templates: templates ?? this.templates,
    );
  }

  OutboundNotificationPolicies copyWithType(
    OutboundNotificationType type,
    OutboundTypePolicy policy,
  ) {
    return copyWith(
      types: {
        ...types,
        type: policy,
      },
    );
  }

  OutboundNotificationPolicies copyWithTemplate(
    OutboundNotificationType type,
    String text,
  ) {
    final next = Map<String, String>.from(templates);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      next.remove(type.dbKey);
    } else {
      next[type.dbKey] = trimmed;
    }
    return copyWith(templates: next);
  }

  factory OutboundNotificationPolicies.fromJson(dynamic raw) {
    if (raw is! Map) return defaults;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final channels = json['channels'];
    final channelMap = channels is Map
        ? channels.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final typesRaw = json['types'];
    final typesMap = typesRaw is Map
        ? typesRaw.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final templatesRaw = json['templates'];
    final templates = <String, String>{};
    if (templatesRaw is Map) {
      for (final entry in templatesRaw.entries) {
        final value = entry.value?.toString().trim() ?? '';
        if (value.isNotEmpty) templates[entry.key.toString()] = value;
      }
    }

    final types = <OutboundNotificationType, OutboundTypePolicy>{};
    for (final type in OutboundNotificationType.values) {
      final fallback = defaults.types[type]!;
      final rawType = typesMap[type.dbKey];
      Map<String, dynamic>? typeJson;
      if (rawType is Map<String, dynamic>) {
        typeJson = rawType;
      } else if (rawType is Map) {
        typeJson = rawType.map((k, v) => MapEntry(k.toString(), v));
      }
      types[type] = OutboundTypePolicy.fromJson(typeJson, fallback: fallback);
    }

    // Pre-V1 JSON stored buyer+hub on a single type. Split in memory so the
    // app matches post-migration behaviour even before SQL is applied.
    if (!typesMap.containsKey(
      OutboundNotificationType.orderNotification.dbKey,
    )) {
      final legacy = types[OutboundNotificationType.orderConfirmation]!;
      if (legacy.sendsTo(OutboundRecipientTarget.hub)) {
        types[OutboundNotificationType.orderNotification] = legacy.copyWith(
          recipients: [OutboundRecipientTarget.hub],
        );
        final kept = [
          for (final target in legacy.recipients)
            if (target != OutboundRecipientTarget.hub) target,
        ];
        types[OutboundNotificationType.orderConfirmation] = legacy.copyWith(
          recipients: kept.isEmpty
              ? const [OutboundRecipientTarget.customer]
              : kept,
        );
      }
    }
    if (!typesMap.containsKey(
      OutboundNotificationType.collectionSubmitted.dbKey,
    )) {
      final legacy = types[OutboundNotificationType.collectionAcknowledgement]!;
      if (legacy.sendsTo(OutboundRecipientTarget.hub)) {
        types[OutboundNotificationType.collectionSubmitted] = legacy.copyWith(
          recipients: [OutboundRecipientTarget.hub],
        );
      }
      types[OutboundNotificationType.collectionAcknowledgement] =
          legacy.copyWith(
        recipients: const [OutboundRecipientTarget.customer],
      );
    }

    return OutboundNotificationPolicies(
      whatsappEnabled: channelMap['whatsapp'] as bool? ?? true,
      smsEnabled: channelMap['sms'] as bool? ?? true,
      types: types,
      templates: templates,
    );
  }

  Map<String, dynamic> toJson() => {
        'channels': {
          'whatsapp': whatsappEnabled,
          'sms': smsEnabled,
        },
        'types': {
          for (final type in OutboundNotificationType.values)
            type.dbKey: policyFor(type).toJson(),
        },
        'templates': templates,
      };

  @override
  List<Object?> get props => [whatsappEnabled, smsEnabled, types, templates];
}
