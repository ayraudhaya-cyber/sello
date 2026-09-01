import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/customers/presentation/hub_customers_page.dart'
    show CustomerEditorDialog;
import 'package:sello/features/hub/inventory/application/hub_inventory_provider.dart';
import 'package:sello/features/hub/orders/application/hub_orders_provider.dart';
import 'package:sello/features/hub/payments/application/hub_payments_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/inventory/presentation/stock_adjust_dialog.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/orders/presentation/order_editor_dialog.dart';
import 'package:sello/features/payments/presentation/receive_payment_dialog.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/quick_action.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/feedback/sello_feedback.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

/// Runs a [QuickActionId] by opening shared dialogs or deeplinking `?new=1`
/// into existing Hub / Sales pages — never forks create logic.
abstract final class QuickActionsLauncher {
  static Future<void> launch(
    BuildContext context,
    WidgetRef ref,
    QuickActionId id,
  ) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    final role = session.appRole;

    switch (id) {
      case QuickActionId.newCustomer:
        if (role.usesHub) {
          context.go('${RoutePaths.hubCustomers}?new=1');
        } else {
          await _newCustomerSales(context, ref);
        }
      case QuickActionId.newProduct:
        context.go('${RoutePaths.hubProducts}?new=1');
      case QuickActionId.newSupplier:
        context.go('${RoutePaths.hubSuppliers}?new=1');
      case QuickActionId.newEmployee:
        context.go('${RoutePaths.hubEmployees}?new=1');
      case QuickActionId.scheduleVisit:
        context.go('${RoutePaths.hubSchedule}?new=1');
      case QuickActionId.stockAdjustment:
        await _stockAdjustment(context, ref);
      case QuickActionId.receivePayment:
        await _receivePayment(context, ref, role);
      case QuickActionId.newOrder:
        await _newOrder(context, ref, role);
      case QuickActionId.startVisit:
        await _startVisit(context, ref);
      case QuickActionId.newWalkIn:
        context.go('${RoutePaths.selloVisit}?walkin=1');
      case QuickActionId.logVisit:
        context.go(RoutePaths.selloCustomers);
    }
  }

  static Future<void> _newCustomerSales(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    final input = await showDialog<CustomerUpsertInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CustomerEditorDialog(),
    );
    if (input == null || !context.mounted) return;

    try {
      await ref
          .read(customerRepositoryProvider)
          .upsertCustomer(
            companyId: session.company.id,
            employeeId: session.employee.id,
            branchId: session.employee.branchId,
            input: input,
          );
      if (!context.mounted) return;
      SelloSnackbars.success(context, 'Customer created.');
    } on AppFailure catch (error) {
      if (!context.mounted) return;
      SelloSnackbars.error(context, error.message);
    }
  }

  static String _currency(WidgetRef ref, UserRole role) {
    final code = role.usesHub
        ? ref.read(companySettingsProvider).currency
        : (ref.read(selloCompanySettingsProvider).valueOrNull ??
                  CompanySettings.defaults)
              .currency;
    return SelloFormatters.currencySymbol(code);
  }

  static Future<void> _receivePayment(
    BuildContext context,
    WidgetRef ref,
    UserRole role,
  ) async {
    final input = await showDialog<ReceivePaymentInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ReceivePaymentDialog(currencySymbol: _currency(ref, role)),
    );
    if (input == null || !context.mounted) return;

    if (role.usesHub) {
      final result = await ref
          .read(hubPaymentsProvider.notifier)
          .receivePayment(input);
      if (!context.mounted) return;
      if (result == null) {
        final message = ref.read(hubPaymentsProvider).errorMessage;
        SelloSnackbars.error(context, message ?? 'Unable to record payment.');
      } else if (result.isPendingReview) {
        await presentCollectionAcknowledgement(context, result.acknowledgement);
      } else {
        SelloSnackbars.success(context, 'Payment recorded.');
      }
      return;
    }

    try {
      final result = await ref
          .read(paymentRepositoryProvider)
          .receivePayment(input);
      if (!context.mounted) return;
      if (result.isPendingReview) {
        await presentCollectionAcknowledgement(context, result.acknowledgement);
      } else {
        SelloSnackbars.success(context, 'Payment recorded.');
      }
    } on AppFailure catch (error) {
      if (!context.mounted) return;
      SelloSnackbars.error(context, error.message);
    }
  }

  static Future<void> _newOrder(
    BuildContext context,
    WidgetRef ref,
    UserRole role,
  ) async {
    if (role.usesSello) {
      // Field sales: orders live inside the visit workspace.
      context.go(RoutePaths.selloCustomers);
      return;
    }

    final result = await showDialog<OrderEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          OrderEditorDialog(currencySymbol: _currency(ref, role)),
    );
    if (result == null || !context.mounted) return;

    final saved = await ref
        .read(hubOrdersProvider.notifier)
        .saveOrder(result.input, complete: result.complete);
    if (!context.mounted) return;
    if (!saved.isOk) {
      SelloSnackbars.error(context, saved.error!);
    } else if (result.complete) {
      await presentOrderConfirmation(
        context,
        saved.confirmation,
        completed: true,
      );
    } else {
      SelloSnackbars.success(context, 'Draft saved.');
    }
  }

  static Future<void> _startVisit(BuildContext context, WidgetRef ref) async {
    // Select customer first — the list is the field-work entry point.
    context.go(RoutePaths.selloCustomers);
  }

  static Future<void> _stockAdjustment(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final item = await showDialog<InventoryItem>(
      context: context,
      builder: (context) => const _QuickInventoryPicker(),
    );
    if (item == null || !context.mounted) return;

    final result = await showDialog<StockAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StockAdjustDialog(item: item),
    );
    if (result == null || !context.mounted) return;

    final error = await ref
        .read(hubInventoryProvider.notifier)
        .adjustStock(result.input);
    if (!context.mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Stock updated.');
    }
  }
}

class _QuickInventoryPicker extends ConsumerStatefulWidget {
  const _QuickInventoryPicker();

  @override
  ConsumerState<_QuickInventoryPicker> createState() =>
      _QuickInventoryPickerState();
}

class _QuickInventoryPickerState extends ConsumerState<_QuickInventoryPicker> {
  final _search = TextEditingController();
  List<InventoryItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(inventoryRepositoryProvider)
          .fetchStock(search: _search.text, pageSize: 40);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Adjust which product?',
                style: context.texts.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SelloSearchBar(
                controller: _search,
                hint: 'Search products or SKU…',
                onChanged: (_) => _load(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return ListTile(
                            title: Text(item.name),
                            subtitle: Text(
                              'SKU ${item.sku} · On hand ${SelloFormatters.quantity(item.quantity)}',
                            ),
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
