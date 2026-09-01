import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/notifications/notification_service.dart';
import 'package:sello/shared/models/app_notification.dart';

/// Canonical business event — published once, consumed by Notifications,
/// Activity Timeline, and (later) Reports / Intelligence / Audit.
class BusinessEvent {
  const BusinessEvent({
    required this.category,
    required this.type,
    required this.title,
    required this.summary,
    this.body,
    this.priority = NotificationPriority.normal,
    this.referenceType,
    this.referenceId,
    this.routeHint,
    this.notifyHubRoles = true,
    this.recipientEmployeeId,
    this.excludeEmployeeId,
    this.emitNotification = true,
    this.logActivity = true,
  });

  final NotificationCategory category;
  final String type;
  final String title;
  final String summary;
  final String? body;
  final NotificationPriority priority;
  final String? referenceType;
  final String? referenceId;
  final String? routeHint;
  final bool notifyHubRoles;
  final String? recipientEmployeeId;
  final String? excludeEmployeeId;
  final bool emitNotification;
  final bool logActivity;
}

/// Shared event bus — domains publish here; never invent module inboxes.
///
/// Today: Notifications + Activity. Future subscribers: Intelligence digests,
/// Reports, Audit logs, webhooks, daily/weekly summaries.
class BusinessEventBus {
  BusinessEventBus({NotificationService? notifications})
    : _notifications = notifications ?? NotificationService();

  final NotificationService _notifications;

  /// Future: attach Intelligence / Reports / webhook adapters here.
  final List<Future<void> Function(BusinessEvent event)> _extraSubscribers = [];

  void addSubscriber(Future<void> Function(BusinessEvent event) subscriber) {
    _extraSubscribers.add(subscriber);
  }

  Future<void> publish({
    required String companyId,
    required BusinessEvent event,
    String? actorEmployeeId,
    String? actorName,
  }) async {
    await _notifications.emit(
      companyId: companyId,
      actorEmployeeId: actorEmployeeId,
      actorName: actorName,
      input: NotificationEmitInput(
        category: event.category,
        type: event.type,
        title: event.title,
        body: event.body ?? event.summary,
        priority: event.priority,
        recipientEmployeeId: event.emitNotification
            ? event.recipientEmployeeId
            : null,
        notifyHubRoles: event.emitNotification && event.notifyHubRoles,
        excludeEmployeeId: event.excludeEmployeeId,
        referenceType: event.referenceType,
        referenceId: event.referenceId,
        routeHint:
            event.routeHint ??
            NotificationDeepLink.hintFor(
              category: event.category,
              referenceType: event.referenceType,
              referenceId: event.referenceId,
            ),
        logActivity: event.logActivity,
        activitySummary: event.summary,
      ),
    );

    for (final subscriber in _extraSubscribers) {
      try {
        await subscriber(event);
      } catch (_) {
        // Subscribers must not break domain writes.
      }
    }
  }
}

/// Convenience factories for common domain events.
abstract final class BusinessEvents {
  // —— Products ————————————————————————————————————————————————

  static BusinessEvent productCreated({
    required String productId,
    required String name,
  }) => BusinessEvent(
    category: NotificationCategory.products,
    type: NotificationTypes.productCreated,
    title: 'Product created',
    summary: 'Product $name was added to the catalog.',
    body: name,
    priority: NotificationPriority.information,
    referenceType: 'product',
    referenceId: productId,
    routeHint: RoutePaths.hubProducts,
  );

  static BusinessEvent productUpdated({
    required String productId,
    required String name,
  }) => BusinessEvent(
    category: NotificationCategory.products,
    type: NotificationTypes.productUpdated,
    title: 'Product updated',
    summary: 'Product $name was updated.',
    body: name,
    priority: NotificationPriority.information,
    referenceType: 'product',
    referenceId: productId,
    routeHint: RoutePaths.hubProducts,
    emitNotification: false,
    logActivity: true,
  );

  static BusinessEvent productArchived({
    required String productId,
    required String name,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.products,
    type: NotificationTypes.productArchived,
    title: 'Product archived',
    summary: 'Product $name was archived.',
    body: name,
    priority: NotificationPriority.information,
    referenceType: 'product',
    referenceId: productId,
    routeHint: RoutePaths.hubProducts,
    excludeEmployeeId: excludeEmployeeId,
  );

  // —— Customers ——————————————————————————————————————————————

  static BusinessEvent customerCreated({
    required String customerId,
    required String name,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.customers,
    type: NotificationTypes.customerCreated,
    title: 'Customer created',
    summary: '$name was added as a customer',
    body: name,
    priority: NotificationPriority.information,
    referenceType: 'customer',
    referenceId: customerId,
    routeHint: RoutePaths.hubCustomers,
    excludeEmployeeId: excludeEmployeeId,
  );

  static BusinessEvent customerArchived({
    required String customerId,
    required String name,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.customers,
    type: NotificationTypes.customerArchived,
    title: 'Customer archived',
    summary: '$name was archived',
    body: name,
    priority: NotificationPriority.information,
    referenceType: 'customer',
    referenceId: customerId,
    routeHint: RoutePaths.hubCustomers,
    excludeEmployeeId: excludeEmployeeId,
  );

  // —— Suppliers ——————————————————————————————————————————————

  static BusinessEvent supplierCreated({
    required String supplierId,
    required String name,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.suppliers,
    type: NotificationTypes.supplierCreated,
    title: 'Supplier created',
    summary: '$name was added as a supplier',
    body: name,
    priority: NotificationPriority.information,
    referenceType: 'supplier',
    referenceId: supplierId,
    routeHint: RoutePaths.hubSuppliers,
    excludeEmployeeId: excludeEmployeeId,
  );

  // —— Orders —————————————————————————————————————————————————

  static BusinessEvent orderCreated({
    required String orderId,
    required String orderNumber,
    required String customerName,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.orders,
    type: NotificationTypes.orderCreated,
    title: 'Order $orderNumber created',
    summary: 'Order $orderNumber created for $customerName',
    body: 'New order for $customerName.',
    priority: NotificationPriority.information,
    referenceType: 'order',
    referenceId: orderId,
    routeHint: RoutePaths.hubOrders,
    excludeEmployeeId: excludeEmployeeId,
  );

  static BusinessEvent orderCompleted({
    required String orderId,
    required String orderNumber,
    required String customerName,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.orders,
    type: NotificationTypes.orderCompleted,
    title: 'Order $orderNumber completed',
    summary: 'Order $orderNumber completed for $customerName',
    body: 'Sale completed for $customerName.',
    priority: NotificationPriority.normal,
    referenceType: 'order',
    referenceId: orderId,
    routeHint: RoutePaths.hubOrders,
    excludeEmployeeId: excludeEmployeeId,
  );

  static BusinessEvent orderCancelled({
    required String orderId,
    required String orderNumber,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.orders,
    type: NotificationTypes.orderCancelled,
    title: 'Order $orderNumber cancelled',
    summary: 'Order $orderNumber was cancelled',
    priority: NotificationPriority.high,
    referenceType: 'order',
    referenceId: orderId,
    routeHint: RoutePaths.hubOrders,
    excludeEmployeeId: excludeEmployeeId,
  );

  // —— Payments ———————————————————————————————————————————————

  static BusinessEvent paymentReceived({
    required String paymentId,
    required String customerName,
  }) => BusinessEvent(
    category: NotificationCategory.payments,
    type: NotificationTypes.paymentReceived,
    title: 'Payment received',
    summary: 'Payment received from $customerName',
    body: 'Collection from $customerName.',
    priority: NotificationPriority.normal,
    referenceType: 'payment',
    referenceId: paymentId,
    routeHint: RoutePaths.hubPayments,
  );

  static BusinessEvent collectionPendingReview({
    required String paymentId,
    required String customerName,
    required String amountLabel,
    String? salesRepName,
  }) => BusinessEvent(
    category: NotificationCategory.payments,
    type: NotificationTypes.collectionPendingReview,
    title: 'Collection awaiting review',
    summary: salesRepName == null
        ? 'Collection of $amountLabel from $customerName needs approval'
        : '$salesRepName submitted $amountLabel from $customerName for review',
    body:
        'Review and approve or reject this collection before balances update.',
    priority: NotificationPriority.high,
    referenceType: 'payment',
    referenceId: paymentId,
    routeHint: RoutePaths.hubPayments,
  );

  static BusinessEvent collectionApproved({
    required String paymentId,
    required String customerName,
  }) => BusinessEvent(
    category: NotificationCategory.payments,
    type: NotificationTypes.collectionApproved,
    title: 'Collection approved',
    summary: 'Collection from $customerName was approved',
    body: 'Balances and payment records have been updated.',
    priority: NotificationPriority.normal,
    referenceType: 'payment',
    referenceId: paymentId,
    routeHint: RoutePaths.hubPayments,
    notifyHubRoles: false,
  );

  static BusinessEvent collectionRejected({
    required String paymentId,
    required String customerName,
  }) => BusinessEvent(
    category: NotificationCategory.payments,
    type: NotificationTypes.collectionRejected,
    title: 'Collection rejected',
    summary: 'Collection from $customerName was rejected',
    body: 'Customer balances were not changed.',
    priority: NotificationPriority.normal,
    referenceType: 'payment',
    referenceId: paymentId,
    routeHint: RoutePaths.hubPayments,
    notifyHubRoles: false,
  );

  // —— Inventory ——————————————————————————————————————————————

  static BusinessEvent stockAdjusted({
    required String productId,
    required String productName,
  }) => BusinessEvent(
    category: NotificationCategory.inventory,
    type: NotificationTypes.stockAdjusted,
    title: 'Inventory adjusted',
    summary: 'Inventory adjusted for $productName',
    body: productName,
    priority: NotificationPriority.information,
    referenceType: 'product',
    referenceId: productId,
    routeHint: RoutePaths.hubInventory,
  );

  static BusinessEvent outOfStock({
    required String productId,
    required String productName,
  }) => BusinessEvent(
    category: NotificationCategory.inventory,
    type: NotificationTypes.outOfStock,
    title: 'Out of stock',
    summary: '$productName is out of stock',
    body: productName,
    priority: NotificationPriority.high,
    referenceType: 'product',
    referenceId: productId,
    routeHint: RoutePaths.hubInventory,
  );

  static BusinessEvent lowStock({
    required String productId,
    required String productName,
  }) => BusinessEvent(
    category: NotificationCategory.inventory,
    type: NotificationTypes.lowStock,
    title: 'Low stock',
    summary: '$productName is low on stock',
    body: '$productName is at or below reorder level.',
    priority: NotificationPriority.high,
    referenceType: 'product',
    referenceId: productId,
    routeHint: RoutePaths.hubInventory,
  );

  // —— Schedule / Visits ——————————————————————————————————————

  static BusinessEvent visitScheduled({
    required String visitId,
    required String recipientEmployeeId,
    NotificationPriority priority = NotificationPriority.normal,
  }) => BusinessEvent(
    category: NotificationCategory.schedule,
    type: NotificationTypes.visitScheduled,
    title: 'Visit scheduled',
    summary: 'A customer visit was scheduled',
    body: 'A customer visit was planned for you.',
    priority: priority,
    notifyHubRoles: false,
    recipientEmployeeId: recipientEmployeeId,
    referenceType: 'visit',
    referenceId: visitId,
    routeHint: RoutePaths.hubSchedule,
  );

  static BusinessEvent routePlanned({
    required String recipientEmployeeId,
    required int stopCount,
    DateTime? visitDate,
    String? area,
    NotificationPriority priority = NotificationPriority.normal,
  }) {
    final areaPart = area == null || area.trim().isEmpty
        ? ''
        : ' in ${area.trim()}';
    final countLabel = '$stopCount ${stopCount == 1 ? 'stop' : 'stops'}';
    return BusinessEvent(
      category: NotificationCategory.schedule,
      type: NotificationTypes.routePlanned,
      title: 'Route planned',
      summary: '$countLabel planned$areaPart',
      body: 'A field route with $countLabel was planned for you$areaPart.',
      priority: priority,
      notifyHubRoles: false,
      recipientEmployeeId: recipientEmployeeId,
      referenceType: 'schedule',
      routeHint: RoutePaths.hubSchedule,
    );
  }

  static BusinessEvent visitCompleted({
    required String visitId,
    required String referenceType,
    required String summary,
    String? body,
    String? routeHint,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.visits,
    type: NotificationTypes.visitCompleted,
    title: 'Visit completed',
    summary: summary,
    body: body,
    priority: NotificationPriority.information,
    referenceType: referenceType,
    referenceId: visitId,
    routeHint: routeHint ?? RoutePaths.hubVisits,
    excludeEmployeeId: excludeEmployeeId,
  );

  static BusinessEvent visitMissed({
    required String visitId,
    required String customerLabel,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.visits,
    type: NotificationTypes.missedVisit,
    title: 'Visit missed',
    summary: 'Visit with $customerLabel was marked missed',
    body: 'Visit with $customerLabel was marked missed.',
    priority: NotificationPriority.high,
    referenceType: 'visit',
    referenceId: visitId,
    routeHint: RoutePaths.hubSchedule,
    excludeEmployeeId: excludeEmployeeId,
  );

  static BusinessEvent followUpRequired({
    required String visitId,
    required String customerLabel,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.visits,
    type: NotificationTypes.followUpRequired,
    title: 'Follow-up required',
    summary: 'Follow up with $customerLabel',
    body: 'Follow up with $customerLabel.',
    priority: NotificationPriority.high,
    referenceType: 'customer_visit',
    referenceId: visitId,
    routeHint: RoutePaths.hubVisits,
    excludeEmployeeId: excludeEmployeeId,
  );

  // —— Team ———————————————————————————————————————————————————

  static BusinessEvent teamMemberJoined({
    required String employeeId,
    required String fullName,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.team,
    type: NotificationTypes.teamMemberJoined,
    title: '$fullName joined the team',
    summary: '$fullName joined the team',
    body: 'A new team member was added.',
    priority: NotificationPriority.information,
    referenceType: 'employee',
    referenceId: employeeId,
    routeHint: RoutePaths.hubEmployees,
    excludeEmployeeId: excludeEmployeeId,
  );

  static BusinessEvent teamMemberInvited({
    required String employeeId,
    required String fullName,
    required String summary,
    String? excludeEmployeeId,
  }) => BusinessEvent(
    category: NotificationCategory.team,
    type: NotificationTypes.teamMemberInvited,
    title: 'Invitation sent',
    summary: summary,
    body: fullName,
    priority: NotificationPriority.information,
    referenceType: 'employee',
    referenceId: employeeId,
    routeHint: RoutePaths.hubEmployees,
    excludeEmployeeId: excludeEmployeeId,
  );

  // —— Reliability ————————————————————————————————————————————

  static BusinessEvent syncFailed({required int failedCount}) => BusinessEvent(
    category: NotificationCategory.reliability,
    type: NotificationTypes.syncFailed,
    title: 'Sync needs attention',
    summary: failedCount == 1
        ? '1 change could not sync. Sello will keep retrying.'
        : '$failedCount changes could not sync. Sello will keep retrying.',
    priority: NotificationPriority.high,
    referenceType: 'reliability',
    routeHint: RoutePaths.hubSettings,
  );

  static BusinessEvent syncCompleted({required int succeeded}) => BusinessEvent(
    category: NotificationCategory.reliability,
    type: NotificationTypes.syncCompleted,
    title: 'Sync complete',
    summary: succeeded == 1
        ? '1 queued change synced successfully.'
        : '$succeeded queued changes synced successfully.',
    priority: NotificationPriority.information,
    referenceType: 'reliability',
    routeHint: RoutePaths.hubSettings,
    emitNotification: false,
    logActivity: true,
  );

  // —— Sello Intelligence —————————————————————————————————————

  static BusinessEvent intelligenceInsight({
    required String title,
    required String summary,
  }) => BusinessEvent(
    category: NotificationCategory.intelligence,
    type: NotificationTypes.intelligenceInsight,
    title: title,
    summary: summary,
    priority: NotificationPriority.normal,
    referenceType: 'intelligence',
    routeHint: RoutePaths.hubReports,
  );
}
