import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/employees/presentation/employee_details_dialog.dart';
import 'package:sello/features/hub/employees/application/hub_employees_provider.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/shared/models/branch.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/employee_summary.dart';
import 'package:sello/shared/models/employee_upsert_input.dart';
import 'package:sello/shared/models/employment_status.dart';
import 'package:sello/shared/models/role.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/models/team_invite_result.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/utils/quick_new_query.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubEmployeesPage extends ConsumerStatefulWidget {
  const HubEmployeesPage({super.key});

  @override
  ConsumerState<HubEmployeesPage> createState() => _HubEmployeesPageState();
}

class _HubEmployeesPageState extends ConsumerState<HubEmployeesPage>
    with QuickNewQueryMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;
  static final _lastActiveFmt = DateFormat('dd MMM yyyy');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    consumeQuickNewQuery(
      cleanPath: RoutePaths.hubEmployees,
      open: () => _openEditor(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toastInvite(TeamInviteResult invite, {required bool isCreate}) {
    if (invite.emailDelivered) {
      SelloSnackbars.success(
        context,
        isCreate
            ? 'Team member added. Invitation email sent.'
            : 'Invitation email sent.',
      );
      return;
    }
    if (invite.emailUnavailable) {
      SelloSnackbars.success(
        context,
        isCreate
            ? 'Team member added, but the invitation email could not be sent. '
                  'Check email delivery settings, then resend from their profile.'
            : 'Account is ready, but the invitation email could not be sent. '
                  'Check email delivery settings and try again.',
      );
      return;
    }
    SelloSnackbars.success(
      context,
      isCreate ? 'Team member added.' : 'Invitation updated.',
    );
  }

  Future<void> _openEditor({EmployeeSummary? employee}) async {
    final state = ref.read(hubEmployeesProvider);
    final result = await showDialog<EmployeeUpsertInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EmployeeEditorDialog(
        employee: employee,
        roles: state.roles,
        branches: state.branches,
      ),
    );
    if (result == null) return;

    final error = await ref
        .read(hubEmployeesProvider.notifier)
        .saveEmployee(
          result,
          onInvite: (invite) => _toastInvite(invite, isCreate: true),
        );
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else if (employee != null) {
      SelloSnackbars.success(context, 'Team member updated.');
    }
  }

  Future<void> _openDetails(EmployeeSummary employee) async {
    final notifier = ref.read(hubEmployeesProvider.notifier);
    final activity = await notifier.loadActivity(employee);
    final assignments = await notifier.loadAssignments(employee);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => EmployeeDetailsDialog(
        employee: employee,
        activity: activity,
        assignments: assignments,
        onEdit: () {
          Navigator.of(context).pop();
          _openEditor(employee: employee);
        },
        onInvite: employee.hasLogin
            ? null
            : () async {
                Navigator.of(context).pop();
                final error = await notifier.sendLoginInvite(
                  employee,
                  onInvite: (invite) => _toastInvite(invite, isCreate: false),
                );
                if (!mounted) return;
                if (error != null) {
                  SelloSnackbars.error(context, error);
                }
              },
        onAssignCustomer: () async {
          await _assignCustomer(employee);
        },
        onRemoveAssignment: (assignment) async {
          final error = await notifier.removeAssignment(
            employee: employee,
            assignmentId: assignment.id,
          );
          if (!mounted) return;
          if (error != null) {
            SelloSnackbars.error(context, error);
          } else {
            SelloSnackbars.success(context, 'Assignment removed.');
            Navigator.of(context).pop();
            await _openDetails(
              ref
                      .read(hubEmployeesProvider)
                      .items
                      .where((e) => e.id == employee.id)
                      .firstOrNull ??
                  employee,
            );
          }
        },
        onArchive: () async {
          Navigator.of(context).pop();
          final error = await notifier.setStatus(
            employee,
            status: EmploymentStatus.archived,
          );
          if (!mounted) return;
          if (error != null) {
            SelloSnackbars.error(context, error);
          } else {
            SelloSnackbars.success(context, 'Team member archived.');
          }
        },
        onRestore: () async {
          Navigator.of(context).pop();
          final error = await notifier.setStatus(
            employee,
            status: EmploymentStatus.active,
          );
          if (!mounted) return;
          if (error != null) {
            SelloSnackbars.error(context, error);
          } else {
            SelloSnackbars.success(context, 'Team member set to active.');
          }
        },
      ),
    );
  }

  Future<void> _assignCustomer(EmployeeSummary employee) async {
    final result = await ref
        .read(customerRepositoryProvider)
        .fetchCustomers(isActive: true, pageSize: 50);
    if (!mounted) return;
    final selected = await showDialog<CustomerSummary>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign customer'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: result.items.isEmpty
              ? const Text('No active customers to assign.')
              : ListView.builder(
                  itemCount: result.items.length,
                  itemBuilder: (context, index) {
                    final customer = result.items[index];
                    return ListTile(
                      title: Text(customer.name),
                      subtitle: Text(
                        PhoneNumber.displayOrNull(customer.phone) ??
                            customer.email ??
                            '',
                      ),
                      onTap: () => Navigator.of(context).pop(customer),
                    );
                  },
                ),
        ),
        actions: [
          SelloButton(
            label: 'Cancel',
            variant: SelloButtonVariant.outline,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    final error = await ref
        .read(hubEmployeesProvider.notifier)
        .assignCustomer(
          employee: employee,
          customerId: selected.id,
          customerName: selected.name,
        );
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Customer assigned.');
      Navigator.of(context).pop();
      await _openDetails(
        ref
                .read(hubEmployeesProvider)
                .items
                .where((e) => e.id == employee.id)
                .firstOrNull ??
            employee,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubEmployeesProvider);

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Team',
      subtitle:
          'Add people to your business. Their role decides whether they use '
          'Hub or the Sales Rep app.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      actions: [
        SelloButton(
          label: 'Add Team Member',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: state.isSaving ? null : () => _openEditor(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            searchController: _searchController,
            state: state,
            onSearchChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(hubEmployeesProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubEmployeesProvider.notifier).setStatusFilter(value);
              }
            },
            onRoleChanged: (value) {
              if (value != null) {
                ref.read(hubEmployeesProvider.notifier).setRoleFilter(value);
              }
            },
            onBranchChanged: (value) {
              ref.read(hubEmployeesProvider.notifier).setBranchFilter(value);
            },
            onRefresh: state.isLoading
                ? null
                : () => ref.read(hubEmployeesProvider.notifier).refresh(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              const SelloTableSkeleton(columns: 8),
          ] else ...[
            _SummaryRow(stats: state.stats),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load team',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubEmployeesProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              SelloCard(
                child: SelloEmptyState(
                  title: 'No team members yet',
                  message:
                      'Add owners, managers, and sales representatives. '
                      'Sello creates their account and sends an invitation '
                      'automatically.',
                  icon: Icons.groups_rounded,
                  actionLabel: 'Add Team Member',
                  onAction: () => _openEditor(),
                ),
              )
            else if (context.isMobile)
              SelloFadeIn(
                child: Column(
                  children: [
                    for (final emp in state.items) ...[
                      SelloCard(
                        onTap: () => _openDetails(emp),
                        child: Row(
                          children: [
                            SelloEntityThumb(
                              name: emp.fullName,
                              imageUrl: emp.avatarUrl,
                              width: 48,
                              height: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    emp.fullName,
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${emp.role.shortLabelOrName} · '
                                    '${emp.displayEmployeeId}',
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SelloStatusBadge(
                              label: emp.employmentStatus.label,
                              tone: _tone(emp.employmentStatus),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _Pager(
                      page: state.page,
                      hasMore: state.hasMore,
                      onPrev: state.page <= 0
                          ? null
                          : () => ref
                                .read(hubEmployeesProvider.notifier)
                                .goToPage(state.page - 1),
                      onNext: !state.hasMore
                          ? null
                          : () => ref
                                .read(hubEmployeesProvider.notifier)
                                .goToPage(state.page + 1),
                    ),
                  ],
                ),
              )
            else
              SelloFadeIn(
                child: SelloDataTable(
                  columns: [
                    selloDataColumn('Team member'),
                    selloDataColumn('ID'),
                    selloDataColumn('Role'),
                    selloDataColumn('Phone'),
                    selloDataColumn('Status'),
                    selloDataColumn('Customers', numeric: true),
                    selloDataColumn('Last active'),
                    selloDataColumn('Actions'),
                  ],
                  rows: [
                    for (final emp in state.items)
                      DataRow(
                        onSelectChanged: (_) => _openDetails(emp),
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                SelloEntityThumb(
                                  name: emp.fullName,
                                  imageUrl: emp.avatarUrl,
                                  width: 44,
                                  height: 44,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: SelloTableText(
                                    emp.fullName,
                                    tone: SelloTableTone.strong,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(SelloTableText(emp.displayEmployeeId)),
                          DataCell(SelloTableText(emp.role.name)),
                          DataCell(
                            SelloTableText(
                              PhoneNumber.displayOrNull(emp.phone) ?? '—',
                            ),
                          ),
                          DataCell(
                            SelloStatusBadge(
                              label: emp.employmentStatus.label,
                              tone: _tone(emp.employmentStatus),
                            ),
                          ),
                          DataCell(
                            SelloTableText('${emp.assignedCustomerCount}'),
                          ),
                          DataCell(
                            SelloTableText(
                              emp.lastActiveAt == null
                                  ? '—'
                                  : _lastActiveFmt.format(
                                      emp.lastActiveAt!.toLocal(),
                                    ),
                            ),
                          ),
                          DataCell(
                            SelloButton(
                              label: 'View',
                              variant: SelloButtonVariant.ghost,
                              size: SelloButtonSize.small,
                              onPressed: () => _openDetails(emp),
                            ),
                          ),
                        ],
                      ),
                  ],
                  footer: _Pager(
                    page: state.page,
                    hasMore: state.hasMore,
                    onPrev: state.page <= 0
                        ? null
                        : () => ref
                              .read(hubEmployeesProvider.notifier)
                              .goToPage(state.page - 1),
                    onNext: !state.hasMore
                        ? null
                        : () => ref
                              .read(hubEmployeesProvider.notifier)
                              .goToPage(state.page + 1),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static SelloStatusTone _tone(EmploymentStatus status) => switch (status) {
    EmploymentStatus.active => SelloStatusTone.success,
    EmploymentStatus.inactive => SelloStatusTone.neutral,
    EmploymentStatus.suspended => SelloStatusTone.warning,
    EmploymentStatus.archived => SelloStatusTone.danger,
  };
}

extension on Role {
  String get shortLabelOrName {
    switch (code) {
      case 'sales_representative':
        return 'Sales Rep';
      default:
        return name;
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onRoleChanged,
    required this.onBranchChanged,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final HubEmployeesState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<EmployeeStatusFilter?> onStatusChanged;
  final ValueChanged<EmployeeRoleFilter?> onRoleChanged;
  final ValueChanged<String?> onBranchChanged;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final role = SizedBox(
      width: context.isMobile ? double.infinity : 160,
      child: SelloDropdown<EmployeeRoleFilter>(
        value: state.roleFilter,
        compact: true,
        hint: 'Role',
        onChanged: onRoleChanged,
        items: const [
          DropdownMenuItem(
            value: EmployeeRoleFilter.all,
            child: Text('All roles'),
          ),
          DropdownMenuItem(
            value: EmployeeRoleFilter.owner,
            child: Text('Owner'),
          ),
          DropdownMenuItem(
            value: EmployeeRoleFilter.manager,
            child: Text('Manager'),
          ),
          DropdownMenuItem(
            value: EmployeeRoleFilter.salesRepresentative,
            child: Text('Sales Rep'),
          ),
        ],
      ),
    );

    final status = SizedBox(
      width: context.isMobile ? double.infinity : 150,
      child: SelloDropdown<EmployeeStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(
            value: EmployeeStatusFilter.all,
            child: Text('All statuses'),
          ),
          DropdownMenuItem(
            value: EmployeeStatusFilter.active,
            child: Text('Active'),
          ),
          DropdownMenuItem(
            value: EmployeeStatusFilter.inactive,
            child: Text('Inactive'),
          ),
          DropdownMenuItem(
            value: EmployeeStatusFilter.suspended,
            child: Text('Suspended'),
          ),
          DropdownMenuItem(
            value: EmployeeStatusFilter.archived,
            child: Text('Archived'),
          ),
        ],
      ),
    );

    final branch = SizedBox(
      width: context.isMobile ? double.infinity : 170,
      child: SelloDropdown<String?>(
        value: state.branchId,
        compact: true,
        hint: 'Branch',
        onChanged: onBranchChanged,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All branches'),
          ),
          for (final item in state.branches)
            DropdownMenuItem<String?>(value: item.id, child: Text(item.name)),
        ],
      ),
    );

    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      onPressed: onRefresh,
    );

    return SelloListToolbar(
      searchController: searchController,
      searchHint: 'Search name, email, phone, ID…',
      onSearchChanged: onSearchChanged,
      filters: [role, status, branch],
      actions: [refresh],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stats});

  final EmployeeDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      children: [
        SelloStatCard(
          label: 'Team members',
          value: '${stats.total}',
          icon: Icons.groups_outlined,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'Active',
          value: '${stats.active}',
          icon: Icons.check_circle_outline,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Sales representatives',
          value: '${stats.salesRepresentatives}',
          icon: Icons.storefront_outlined,
          tone: AppColors.inventory,
        ),
        SelloStatCard(
          label: 'Managers',
          value: '${stats.managers}',
          icon: Icons.manage_accounts_outlined,
          tone: AppColors.finance,
        ),
        SelloStatCard(
          label: 'Inactive',
          value: '${stats.inactive}',
          icon: Icons.person_off_outlined,
          tone: AppColors.textSecondary,
        ),
      ],
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.hasMore,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final bool hasMore;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Page ${page + 1}',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _EmployeeEditorDialog extends StatefulWidget {
  const _EmployeeEditorDialog({
    required this.roles,
    required this.branches,
    this.employee,
  });

  final EmployeeSummary? employee;
  final List<Role> roles;
  final List<Branch> branches;

  @override
  State<_EmployeeEditorDialog> createState() => _EmployeeEditorDialogState();
}

class _EmployeeEditorDialogState extends State<_EmployeeEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _media = MediaService();
  late final TextEditingController _fullName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _employeeCode;
  late final TextEditingController _nic;
  late final TextEditingController _address;
  late final TextEditingController _department;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _notes;
  late String? _roleId;
  String? _branchId;
  late EmploymentStatus _status;
  DateTime? _joinedAt;
  Uint8List? _avatarBytes;
  bool _clearAvatar = false;
  bool _submitted = false;
  bool _picking = false;

  bool get _isCreate => widget.employee == null;

  Role? get _selectedRole {
    final id = _roleId;
    if (id == null) return null;
    for (final role in widget.roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  String? get _roleGuidance {
    final role = _selectedRole;
    if (role == null) return null;
    return RolePermissionProfile.forRoleCode(role.code).guidance;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _fullName = TextEditingController(text: e?.fullName ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _phone = TextEditingController(text: PhoneNumber.displayOf(e?.phone));
    _employeeCode = TextEditingController(text: e?.employeeCode ?? '');
    _nic = TextEditingController(text: e?.nic ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _department = TextEditingController(text: e?.department ?? '');
    _emergencyName = TextEditingController(text: e?.emergencyContactName ?? '');
    _emergencyPhone = TextEditingController(
      text: PhoneNumber.displayOf(e?.emergencyContactPhone),
    );
    _notes = TextEditingController(text: e?.notes ?? '');
    _roleId =
        e?.roleId ?? (widget.roles.isNotEmpty ? widget.roles.first.id : null);
    _branchId = e?.branchId;
    _status = e?.employmentStatus ?? EmploymentStatus.active;
    _joinedAt = e?.joinedAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _employeeCode.dispose();
    _nic.dispose();
    _address.dispose();
    _department.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _picking = true);
    try {
      final file = await _media.pickWithBestExperience(context);
      if (file == null || !mounted) return;
      final raw = await file.readAsBytes();
      if (!mounted) return;
      final prepared = await _media.prepareForUpload(context, raw);
      if (prepared == null || !mounted) return;
      setState(() {
        _avatarBytes = prepared.bytes;
        _clearAvatar = false;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_roleId == null) {
      SelloSnackbars.error(context, 'Select a role.');
      return;
    }

    Navigator.of(context).pop(
      EmployeeUpsertInput(
        id: widget.employee?.id,
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        roleId: _roleId!,
        employmentStatus: _status,
        phone: PhoneNumber.normalizeStorage(_phone.text),
        employeeCode: _trimOrNull(_employeeCode.text),
        nic: _trimOrNull(_nic.text),
        address: _trimOrNull(_address.text),
        emergencyContactName: _trimOrNull(_emergencyName.text),
        emergencyContactPhone: PhoneNumber.normalizeStorage(
          _emergencyPhone.text,
        ),
        department: _trimOrNull(_department.text),
        joinedAt: _joinedAt,
        branchId: _branchId,
        notes: _trimOrNull(_notes.text),
        clearAvatar: _clearAvatar,
        avatarBytes: _avatarBytes,
      ),
    );
  }

  String? _trimOrNull(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _clearAvatar ? null : widget.employee?.avatarUrl;
    final guidance = _roleGuidance;

    return SelloFormDialog(
      formKey: _formKey,
      maxWidth: kSelloFormDialogWidth,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      title: _isCreate ? 'Add Team Member' : 'Edit team member',
      subtitle: _isCreate
          ? 'Enter their details and choose a role. Sello creates their '
                'account and sends an invitation automatically.'
          : 'Update their details. Their role decides which Sello experience '
                'they use.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloDialogSection(
            title: 'Personal Information',
            children: [
              Row(
                children: [
                  if (_avatarBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _avatarBytes!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    SelloEntityThumb(
                      name: _fullName.text.isEmpty ? 'T' : _fullName.text,
                      imageUrl: previewUrl,
                      width: 72,
                      height: 72,
                    ),
                  const SizedBox(width: 16),
                  SelloButton(
                    label: _picking ? 'Processing…' : 'Upload photo',
                    variant: SelloButtonVariant.outline,
                    size: SelloButtonSize.small,
                    onPressed: _picking ? null : _pickAvatar,
                  ),
                  if (previewUrl != null || _avatarBytes != null) ...[
                    const SizedBox(width: 8),
                    SelloButton(
                      label: 'Remove',
                      variant: SelloButtonVariant.ghost,
                      size: SelloButtonSize.small,
                      onPressed: () => setState(() {
                        _avatarBytes = null;
                        _clearAvatar = true;
                      }),
                    ),
                  ],
                ],
              ),
              SelloTextField(
                controller: _fullName,
                label: 'Full name',
                required: true,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name.' : null,
              ),
              SelloFormRow(
                left: SelloTextField(
                  controller: _phone,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                  validator: PhoneNumber.validator,
                ),
                right: SelloTextField(
                  controller: _email,
                  label: 'Email',
                  required: true,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Enter an email.';
                    if (!t.contains('@')) return 'Enter a valid email.';
                    return null;
                  },
                ),
              ),
              SelloTextField(controller: _nic, label: 'NIC / Identification'),
              SelloTextField(
                controller: _address,
                label: 'Address',
                maxLines: 2,
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Employment',
            children: [
              SelloDropdown<String>(
                label: 'Role',
                required: true,
                value: _roleId,
                items: [
                  for (final role in widget.roles)
                    DropdownMenuItem(value: role.id, child: Text(role.name)),
                ],
                onChanged: (value) => setState(() => _roleId = value),
              ),
              if (guidance != null) ...[
                const SizedBox(height: 8),
                Text(
                  guidance,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SelloDropdown<String?>(
                label: 'Branch',
                value: _branchId,
                hint: widget.branches.isEmpty
                    ? 'No branches yet'
                    : 'Select branch',
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  for (final branch in widget.branches)
                    DropdownMenuItem<String?>(
                      value: branch.id,
                      child: Text(branch.name),
                    ),
                ],
                onChanged: (value) => setState(() => _branchId = value),
              ),
              SelloFormRow(
                left: SelloTextField(
                  controller: _department,
                  label: 'Department',
                ),
                right: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _joinedAt ?? DateTime.now(),
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) setState(() => _joinedAt = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Joined date',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      SelloFormatters.date(_joinedAt),
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                      ),
                    ),
                  ),
                ),
              ),
              SelloFormRow(
                left: SelloDropdown<EmploymentStatus>(
                  label: 'Status',
                  value: _status,
                  items: [
                    for (final s in EmploymentStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
                right: SelloTextField(
                  controller: _employeeCode,
                  label: 'Member ID',
                  hint: 'Auto if blank',
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Emergency Contact',
            children: [
              SelloFormRow(
                left: SelloTextField(
                  controller: _emergencyName,
                  label: 'Contact name',
                ),
                right: SelloTextField(
                  controller: _emergencyPhone,
                  label: 'Contact phone',
                  keyboardType: TextInputType.phone,
                  validator: PhoneNumber.validator,
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Notes',
            bottomSpacing: 8,
            children: [
              SelloTextField(
                controller: _notes,
                label: 'Notes',
                hint: 'Internal notes',
                maxLines: 3,
              ),
            ],
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.of(context).maybePop(),
        primaryLabel: _isCreate ? 'Add Team Member' : 'Save changes',
        onPrimary: _submit,
      ),
    );
  }
}
