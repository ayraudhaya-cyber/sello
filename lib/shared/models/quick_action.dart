import 'package:flutter/material.dart';
import 'package:sello/shared/models/user_role.dart';

/// Stable ids for quick actions — safe for analytics / recently-used later.
enum QuickActionId {
  newCustomer,
  newProduct,
  newSupplier,
  newEmployee,
  scheduleVisit,
  receivePayment,
  stockAdjustment,
  startVisit,
  newWalkIn,
  newOrder,
  logVisit,
}

/// One day-to-day action in the Quick Actions workspace.
///
/// Launching is handled by [QuickActionsLauncher] so create/payment/visit
/// flows stay in shared dialogs and page notifiers — never duplicated here.
class QuickActionDefinition {
  const QuickActionDefinition({
    required this.id,
    required this.label,
    required this.icon,
    required this.roles,
    this.subtitle,
    this.shortcutLabel,
  });

  final QuickActionId id;
  final String label;
  final IconData icon;

  /// Who may see this action. Empty = none.
  final Set<UserRole> roles;

  /// Optional supporting line for future rich menus.
  final String? subtitle;

  /// Future keyboard hint (e.g. "C"). Not bound yet.
  final String? shortcutLabel;

  bool isAvailableFor(UserRole role) => roles.contains(role);
}

/// Role-filtered catalog. Extend here for context / recently-used later.
abstract final class QuickActionsCatalog {
  static const List<QuickActionDefinition> all = [
    QuickActionDefinition(
      id: QuickActionId.newCustomer,
      label: 'New Customer',
      icon: Icons.person_add_alt_1_rounded,
      subtitle: 'Add a buyer to your book',
      roles: {UserRole.owner, UserRole.manager, UserRole.salesRepresentative},
      shortcutLabel: 'C',
    ),
    QuickActionDefinition(
      id: QuickActionId.newProduct,
      label: 'New Product',
      icon: Icons.inventory_2_outlined,
      subtitle: 'Add something you sell',
      roles: {UserRole.owner, UserRole.manager},
      shortcutLabel: 'P',
    ),
    QuickActionDefinition(
      id: QuickActionId.newSupplier,
      label: 'New Supplier',
      icon: Icons.local_shipping_outlined,
      subtitle: 'Add a sourcing partner',
      roles: {UserRole.owner, UserRole.manager},
    ),
    QuickActionDefinition(
      id: QuickActionId.newEmployee,
      label: 'New Employee',
      icon: Icons.badge_outlined,
      subtitle: 'Invite someone to the team',
      roles: {UserRole.owner, UserRole.manager},
    ),
    QuickActionDefinition(
      id: QuickActionId.scheduleVisit,
      label: 'Schedule Visit',
      icon: Icons.event_available_rounded,
      subtitle: 'Plan a customer stop',
      roles: {UserRole.owner, UserRole.manager},
    ),
    QuickActionDefinition(
      id: QuickActionId.receivePayment,
      label: 'Receive Payment',
      icon: Icons.payments_outlined,
      subtitle: 'Record a collection',
      roles: {UserRole.owner, UserRole.manager, UserRole.salesRepresentative},
      shortcutLabel: 'M',
    ),
    QuickActionDefinition(
      id: QuickActionId.stockAdjustment,
      label: 'Stock Adjustment',
      icon: Icons.tune_rounded,
      subtitle: 'Correct on-hand quantity',
      roles: {UserRole.owner, UserRole.manager},
    ),
    QuickActionDefinition(
      id: QuickActionId.startVisit,
      label: 'Start Visit',
      icon: Icons.storefront_outlined,
      subtitle: 'Pick a customer and open the visit',
      roles: {UserRole.salesRepresentative},
      shortcutLabel: 'V',
    ),
    QuickActionDefinition(
      id: QuickActionId.newWalkIn,
      label: 'New Walk-in',
      icon: Icons.add_business_outlined,
      subtitle: 'Show products first — register only if they buy',
      roles: {UserRole.salesRepresentative},
    ),
    QuickActionDefinition(
      id: QuickActionId.newOrder,
      label: 'New Order',
      icon: Icons.receipt_long_outlined,
      subtitle: 'Build a basket and sell',
      roles: {UserRole.owner, UserRole.manager, UserRole.salesRepresentative},
      shortcutLabel: 'O',
    ),
    QuickActionDefinition(
      id: QuickActionId.logVisit,
      label: 'Log Visit',
      icon: Icons.place_outlined,
      subtitle: 'Jump to today’s visit list',
      roles: {UserRole.salesRepresentative},
    ),
  ];

  /// Short, practical list for the signed-in role (stable day-to-day order).
  ///
  /// Later: prepend recently-used / inject context-aware entries without
  /// changing [all] definitions.
  static List<QuickActionDefinition> forRole(UserRole role) {
    final byId = {for (final action in all) action.id: action};
    final order = switch (role) {
      UserRole.owner || UserRole.manager => const [
          QuickActionId.newCustomer,
          QuickActionId.newProduct,
          QuickActionId.newSupplier,
          QuickActionId.newEmployee,
          QuickActionId.scheduleVisit,
          QuickActionId.receivePayment,
          QuickActionId.stockAdjustment,
          QuickActionId.newOrder,
        ],
      UserRole.salesRepresentative => const [
          QuickActionId.startVisit,
          QuickActionId.newWalkIn,
          QuickActionId.newOrder,
          QuickActionId.receivePayment,
          QuickActionId.logVisit,
          QuickActionId.newCustomer,
        ],
    };
    return [
      for (final id in order) ?byId[id],
    ];
  }
}
