import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/inventory/application/hub_inventory_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/features/hub/suppliers/application/hub_supplier_orders_provider.dart';
import 'package:sello/features/hub/suppliers/application/hub_suppliers_provider.dart';
import 'package:sello/features/hub/suppliers/presentation/supplier_order_details_dialog.dart';
import 'package:sello/features/hub/suppliers/presentation/supplier_order_editor_dialog.dart';
import 'package:sello/features/hub/suppliers/presentation/supplier_order_print.dart';
import 'package:sello/shared/models/supplier_order.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sello/data/providers/repository_providers.dart';

class HubSupplierOrdersPanel extends ConsumerStatefulWidget {
  const HubSupplierOrdersPanel({required this.currencySymbol, this.onCreate});

  final String currencySymbol;
  final VoidCallback? onCreate;

  @override
  ConsumerState<HubSupplierOrdersPanel> createState() =>
      _HubSupplierOrdersPanelState();
}

class _HubSupplierOrdersPanelState extends ConsumerState<HubSupplierOrdersPanel> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final state = ref.read(hubSupplierOrdersProvider);
      if (!state.initialized) {
        ref.read(hubSupplierOrdersProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshBalances() async {
    await ref.read(hubSuppliersProvider.notifier).refresh();
    await ref.read(hubInventoryProvider.notifier).refresh();
  }

  Future<void> _open(SupplierOrderSummary summary) async {
    final detail = await ref
        .read(supplierOrderRepositoryProvider)
        .fetchById(summary.id);
    if (!mounted) return;
    final updated = await showDialog<SupplierOrderSummary>(
      context: context,
      builder: (context) => SupplierOrderDetailsDialog(
        order: detail,
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (!mounted) return;
    await ref.read(hubSupplierOrdersProvider.notifier).load(showLoading: false);
    if (updated != null) await _refreshBalances();
  }

  Future<void> _edit(SupplierOrderSummary summary) async {
    final detail = await ref
        .read(supplierOrderRepositoryProvider)
        .fetchById(summary.id);
    if (!mounted) return;
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SupplierOrderEditorDialog(
        existing: detail,
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (id == null || !mounted) return;
    await ref.read(hubSupplierOrdersProvider.notifier).load(showLoading: false);
    if (!mounted) return;
    SelloSnackbars.success(context, 'Order saved.');
  }

  Future<void> _print(SupplierOrderSummary summary) async {
    final detail = await ref
        .read(supplierOrderRepositoryProvider)
        .fetchById(summary.id);
    if (!mounted) return;
    printSupplierOrder(detail, widget.currencySymbol, _issuer());
  }

  Future<void> _whatsApp(SupplierOrderSummary summary) async {
    final detail = await ref
        .read(supplierOrderRepositoryProvider)
        .fetchById(summary.id);
    if (!mounted) return;
    final phone = PhoneNumber.tryParse(
      detail.supplierWhatsapp ?? detail.supplierPhone,
    );
    if (phone == null) {
      SelloSnackbars.warning(
        context,
        'Add a WhatsApp number on this supplier first.',
      );
      return;
    }
    final text = Uri.encodeComponent(_whatsAppBody(detail));
    final uri = Uri.parse('https://wa.me/${phone.whatsappDigits}?text=$text');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      SelloSnackbars.error(context, 'Unable to open WhatsApp.');
    }
  }

  DocumentIssuerIdentity _issuer() {
    final session = ref.read(currentSessionProvider);
    final settings = ref.read(companySettingsProvider);
    final name = session?.company.name.trim() ?? '';
    return DocumentIssuerIdentity.resolve(
      companyName: name.isEmpty ? 'Business' : name,
      documentLogoUrl: settings.documentLogoUrl,
      showBusinessNameWithLogo: settings.documentShowBusinessNameWithLogo,
      address: settings.documentAddress,
      phone: settings.documentPhone,
      email: settings.documentEmail,
    );
  }

  String _whatsAppBody(SupplierOrderSummary order) {
    final identity = _issuer();
    final business = identity.businessName;
    final lines = order.lines
        .map(
          (line) =>
              '${line.title} — ${SelloFormatters.quantity(line.quantity)}',
        )
        .join('\n');
    final total = SelloFormatters.currency(
      order.total,
      symbol: widget.currencySymbol,
    );
    final pay = order.paymentMethod == null
        ? ''
        : '\nPayment: ${order.paymentMethod!.label}';
    final phone = identity.phone == null ? '' : '\n${identity.phone}';
    return 'Hi ${order.supplierName}\n'
        '\n'
        'Purchase order ${order.orderNumber} from $business.\n'
        '\n'
        '$lines\n'
        '\n'
        'Order value: $total$pay\n'
        '\n'
        'Please confirm when you can deliver.\n'
        '\n'
        '$business$phone';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubSupplierOrdersProvider);
    if (_search.text != state.search) {
      _search.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: context.isMobile ? double.infinity : 320,
              child: SelloSearchBar(
                controller: _search,
                hint: 'Order number or supplier',
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => ref
                        .read(hubSupplierOrdersProvider.notifier)
                        .setSearch(value),
                  );
                },
              ),
            ),
            SelloButton(
              label: 'Refresh',
              icon: Icons.refresh_rounded,
              variant: SelloButtonVariant.outline,
              loading: state.isLoading,
              onPressed: state.isLoading
                  ? null
                  : () => ref.read(hubSupplierOrdersProvider.notifier).load(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        if (state.errorMessage != null && state.items.isEmpty)
          SelloEmptyState(
            title: 'Unable to load supplier orders',
            message: state.errorMessage,
            icon: Icons.error_outline_rounded,
            tone: EmptyStateTone.warning,
            actionLabel: 'Try again',
            onAction: () => ref.read(hubSupplierOrdersProvider.notifier).load(),
          )
        else if (state.isLoading && state.items.isEmpty)
          context.isMobile
              ? const SelloListSkeleton()
              : const SelloTableSkeleton(columns: 6, showMetrics: false)
        else if (state.items.isEmpty)
          SelloEmptyState(
            title: state.search.trim().isEmpty
                ? 'No supplier orders yet'
                : 'No matching orders',
            message: state.search.trim().isEmpty
                ? 'Place an order, then receive the goods on that same order.'
                : 'Try another order number or supplier.',
            icon: Icons.local_shipping_outlined,
            actionLabel: widget.onCreate == null ? null : 'New order',
            onAction: widget.onCreate,
          )
        else
          SelloDataTable(
            minWidth: 920,
            flexColumnIndex: 1,
            columns: const [
              DataColumn(label: Text('Order')),
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Total')),
              DataColumn(label: Text('Owed')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final order in state.items)
                DataRow(
                  cells: [
                    DataCell(Text(order.orderNumber)),
                    DataCell(Text(order.supplierName)),
                    DataCell(
                      SelloStatusBadge(
                        label: order.status.label,
                        compact: true,
                        showDot: false,
                        tone: switch (order.status) {
                          SupplierOrderStatus.received =>
                            SelloStatusTone.success,
                          SupplierOrderStatus.partiallyReceived =>
                            SelloStatusTone.warning,
                          SupplierOrderStatus.awaitingDelivery =>
                            SelloStatusTone.info,
                          _ => SelloStatusTone.neutral,
                        },
                      ),
                    ),
                    DataCell(
                      Text(
                        SelloFormatters.currency(
                          order.total,
                          symbol: widget.currencySymbol,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        SelloFormatters.currency(
                          order.stillOwed,
                          symbol: widget.currencySymbol,
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelloRowIconButton(
                            tooltip: 'View',
                            icon: Icons.visibility_outlined,
                            onPressed: () => _open(order),
                          ),
                          if (order.canEditLines)
                            SelloRowIconButton(
                              tooltip: 'Edit',
                              icon: Icons.edit_outlined,
                              onPressed: () => _edit(order),
                            ),
                          if (order.status.canShare) ...[
                            SelloRowIconButton(
                              tooltip: 'Print',
                              icon: Icons.print_outlined,
                              onPressed: () => _print(order),
                            ),
                            SelloRowIconButton(
                              tooltip: 'WhatsApp',
                              icon: Icons.chat_outlined,
                              onPressed: () => _whatsApp(order),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
            ],
            footer: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: state.page == 0
                      ? null
                      : () => ref
                          .read(hubSupplierOrdersProvider.notifier)
                          .goToPage(state.page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page ${state.page + 1}'),
                IconButton(
                  onPressed: state.hasMore
                      ? () => ref
                          .read(hubSupplierOrdersProvider.notifier)
                          .goToPage(state.page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
