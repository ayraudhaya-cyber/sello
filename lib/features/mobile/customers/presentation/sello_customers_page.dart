import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/customers/presentation/customer_details_dialog.dart';
import 'package:sello/features/mobile/customers/application/sello_customers_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Field-work entry — pick a customer (or walk-in) and open the visit workspace.
class SelloCustomersPage extends ConsumerStatefulWidget {
  const SelloCustomersPage({super.key});

  @override
  ConsumerState<SelloCustomersPage> createState() => _SelloCustomersPageState();
}

class _SelloCustomersPageState extends ConsumerState<SelloCustomersPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String? _appliedQuery;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final q = GoRouterState.of(context).uri.queryParameters['q'];
    if (q == null || q.isEmpty || q == _appliedQuery) return;
    _appliedQuery = q;
    _searchController.text = q;
    Future.microtask(() {
      if (mounted) {
        ref.read(selloCustomersProvider.notifier).setSearch(q);
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startVisit(CustomerSummary customer) {
    context.go(
      '${RoutePaths.selloVisit}'
      '?customer=${customer.id}'
      '&name=${Uri.encodeComponent(customer.name)}',
    );
  }

  void _startWalkIn() {
    context.go('${RoutePaths.selloVisit}?walkin=1');
  }

  Future<void> _openDetails(CustomerSummary customer) async {
    final session = ref.read(currentSessionProvider);
    String? assigneeName;
    if (session != null) {
      final assignee = await ref
          .read(employeeRepositoryProvider)
          .fetchCustomerAssignee(
            companyId: session.company.id,
            customerId: customer.id,
          );
      assigneeName = assignee.employeeName;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CustomerDetailsDialog(
        customer: customer,
        readOnly: true,
        enableVisitActions: true,
        assignedRepresentativeName: assigneeName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(selloCustomersProvider);

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Customers',
      showBreadcrumbs: false,
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.sm,
      actions: [
        SelloButton(
          label: 'Walk-in',
          icon: Icons.add_rounded,
          size: SelloButtonSize.small,
          onPressed: _startWalkIn,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloTextField(
            controller: _searchController,
            hint: 'Search stores or customers',
            prefixIcon: Icons.search_rounded,
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 300),
                () => ref
                    .read(selloCustomersProvider.notifier)
                    .setSearch(value),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.isLoading && state.items.isEmpty)
            const SelloListSkeleton()
          else if (state.errorMessage != null && state.items.isEmpty)
            SizedBox(
              height: 240,
              child: SelloStateView.error(
                title: 'Unable to load',
                message: state.errorMessage,
                actionLabel: 'Retry',
                onAction: () =>
                    ref.read(selloCustomersProvider.notifier).refresh(),
              ),
            )
          else if (state.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: SelloEmptyState(
                title: 'No customers',
                message: null,
                icon: Icons.storefront_outlined,
                actionLabel: 'Walk-in',
                onAction: _startWalkIn,
              ),
            )
          else
            SelloFadeIn(
              child: Column(
                children: [
                  for (final customer in state.items) ...[
                    _CustomerRow(
                      customer: customer,
                      onVisit: () => _startVisit(customer),
                      onDetails: () => _openDetails(customer),
                    ),
                    const Divider(height: 1, color: AppColors.outlineSubtle),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.onVisit,
    required this.onDetails,
  });

  final CustomerSummary customer;
  final VoidCallback onVisit;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final areaPhone = [
      if (customer.city != null) customer.city!,
      if (customer.phone != null) PhoneNumber.displayOf(customer.phone),
    ].join(' · ');

    return InkWell(
      onTap: onVisit,
      onLongPress: onDetails,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (areaPhone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      areaPhone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.selloColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (customer.outstandingBalance > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                SelloFormatters.currency(customer.outstandingBalance),
                style: context.texts.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
