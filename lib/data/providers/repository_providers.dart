import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/repositories/company_settings_repository.dart';
import 'package:sello/data/repositories/customer_repository.dart';
import 'package:sello/data/repositories/employee_repository.dart';
import 'package:sello/data/repositories/inventory_repository.dart';
import 'package:sello/data/repositories/order_document_repository.dart';
import 'package:sello/data/repositories/order_repository.dart';
import 'package:sello/data/repositories/payment_repository.dart';
import 'package:sello/data/repositories/notification_repository.dart';
import 'package:sello/data/repositories/product_fields_repository.dart';
import 'package:sello/data/repositories/product_repository.dart';
import 'package:sello/data/repositories/report_repository.dart';
import 'package:sello/data/repositories/subscription_repository.dart';
import 'package:sello/data/repositories/supplier_repository.dart';
import 'package:sello/data/repositories/visit_repository.dart';
import 'package:sello/services/iam/audit_service.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/notifications/notification_service.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/services/notifications/outbound/supabase_outbound_sms_sender.dart';
import 'package:sello/services/notifications/supabase_order_confirmation_gateway.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/audit_event.dart';

/// Shared domain repositories — used by Hub and Sales workspaces.
///
/// Keep providers here (not under `features/hub`) so Sales never imports Hub.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final businessEventBusProvider = Provider<BusinessEventBus>(
  (ref) {
    final bus = BusinessEventBus(
      notifications: ref.watch(notificationServiceProvider),
    );
    final audit = AuditService();
    bus.addSubscriber((event) async {
      // Best-effort audit mirror of domain events.
      final companyId = ref.read(currentSessionProvider)?.company.id;
      if (companyId == null) return;
      await audit.log(
        companyId: companyId,
        actorEmployeeId: ref.read(currentSessionProvider)?.employee.id,
        actorName: ref.read(currentSessionProvider)?.displayName,
        input: AuditLogInput(
          action: event.type,
          summary: event.summary,
          moduleKey: event.category.name,
          referenceType: event.referenceType,
          referenceId: event.referenceId,
        ),
      );
    });
    return bus;
  },
);


final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(events: ref.watch(businessEventBusProvider)),
);

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(events: ref.watch(businessEventBusProvider)),
);

final orderDocumentRepositoryProvider = Provider<OrderDocumentRepository>(
  (ref) => OrderDocumentRepository(),
);

/// Server-side SMS (Text.lk). Never constructed with an API token in Dart.
final outboundSmsSenderProvider = Provider<OutboundSmsSender>(
  (ref) => SupabaseOutboundSmsSender(),
);

final orderConfirmationDispatcherProvider =
    Provider<OrderConfirmationDispatcher>(
  (ref) {
    final repo = ref.watch(orderDocumentRepositoryProvider);
    return OrderConfirmationDispatcher(
      gateway: SupabaseOrderConfirmationGateway(repo),
      policiesResolver: () => repo.fetchOutboundPolicies(),
      smsSender: ref.watch(outboundSmsSenderProvider),
    );
  },
);

final collectionAcknowledgementDispatcherProvider =
    Provider<CollectionAcknowledgementDispatcher>(
  (ref) {
    final repo = ref.watch(orderDocumentRepositoryProvider);
    return CollectionAcknowledgementDispatcher(
      prepare: repo.prepareCollectionAcknowledgement,
      recordDispatch: ({
        required String eventId,
        required OutboundChannel channel,
        required OutboundRecipientKind recipientKind,
        required String recipientKey,
        String? address,
        OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
        String? skipReason,
      }) {
        return repo.recordDispatch(
          eventId: eventId,
          channel: channel,
          recipientKind: recipientKind,
          recipientKey: recipientKey,
          address: address,
          status: status,
          skipReason: skipReason,
        );
      },
      policiesResolver: () => repo.fetchOutboundPolicies(),
      smsSender: ref.watch(outboundSmsSenderProvider),
    );
  },
);

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(
    events: ref.watch(businessEventBusProvider),
    confirmations: ref.watch(orderConfirmationDispatcherProvider),
  ),
);

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(
    events: ref.watch(businessEventBusProvider),
    collectionAcknowledgements:
        ref.watch(collectionAcknowledgementDispatcherProvider),
  ),
);

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(events: ref.watch(businessEventBusProvider)),
);

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => EmployeeRepository(events: ref.watch(businessEventBusProvider)),
);

final supplierRepositoryProvider = Provider<SupplierRepository>(
  (ref) => SupplierRepository(events: ref.watch(businessEventBusProvider)),
);

final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(events: ref.watch(businessEventBusProvider)),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(),
);

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(
    inventory: ref.watch(inventoryRepositoryProvider),
    payments: ref.watch(paymentRepositoryProvider),
    orders: ref.watch(orderRepositoryProvider),
    suppliers: ref.watch(supplierRepositoryProvider),
    visits: ref.watch(visitRepositoryProvider),
  ),
);

final companySettingsRepositoryProvider = Provider<CompanySettingsRepository>(
  (ref) => CompanySettingsRepository(),
);

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(),
);

final productFieldsRepositoryProvider = Provider<ProductFieldsRepository>(
  (ref) => ProductFieldsRepository(),
);
