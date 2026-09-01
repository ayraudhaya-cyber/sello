import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/employee_activity_event.dart';
import 'package:sello/shared/models/employee_assignment.dart';
import 'package:sello/shared/models/employee_summary.dart';
import 'package:sello/shared/models/employment_status.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Shared employee profile workspace (Hub today; Sales self-service later).
class EmployeeDetailsDialog extends StatelessWidget {
  const EmployeeDetailsDialog({
    super.key,
    required this.employee,
    required this.activity,
    this.assignments = const [],
    this.onEdit,
    this.onInvite,
    this.onAssignCustomer,
    this.onRemoveAssignment,
    this.onArchive,
    this.onRestore,
  });

  final EmployeeSummary employee;
  final List<EmployeeActivityEvent> activity;
  final List<EmployeeAssignment> assignments;
  final VoidCallback? onEdit;
  final VoidCallback? onInvite;
  final VoidCallback? onAssignCustomer;
  final ValueChanged<EmployeeAssignment>? onRemoveAssignment;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  static final _dateTime = DateFormat('dd MMM yyyy · HH:mm');

  @override
  Widget build(BuildContext context) {
    final profile = employee.permissionProfile;
    final dash = '—';
    final customerAssignments = assignments
        .where((a) => a.assignmentType == EmployeeAssignmentType.customer)
        .toList();

    return SelloFormDialog(
      title: employee.fullName,
      subtitle: '${employee.role.name} · ${employee.displayEmployeeId}',
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelloEntityThumb(
                name: employee.fullName,
                imageUrl: employee.avatarUrl,
                width: 88,
                height: 88,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SelloMetaPill(value: employee.role.name),
                    SelloStatusBadge(
                      label: employee.employmentStatus.label,
                      tone: _statusTone(employee.employmentStatus),
                    ),
                    SelloStatusBadge(
                      label: employee.hasLogin
                          ? 'On Sello'
                          : 'Invitation pending',
                      tone: employee.hasLogin
                          ? SelloStatusTone.success
                          : SelloStatusTone.warning,
                    ),
                    if (employee.department != null &&
                        employee.department!.isNotEmpty)
                      SelloMetaPill(value: employee.department!),
                    if (employee.branchName != null)
                      SelloMetaPill(value: employee.branchName!),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Personal Information',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(label: 'Full name', value: employee.fullName),
                  right: _Field(
                    label: 'Member ID',
                    value: employee.displayEmployeeId,
                  ),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'Phone',
                    value: PhoneNumber.displayOrNull(employee.phone) ?? dash,
                    muted: employee.phone == null,
                  ),
                  right: _Field(label: 'Email', value: employee.email),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'Address',
                    value: employee.address ?? dash,
                    muted: employee.address == null,
                  ),
                  right: _Field(
                    label: 'NIC / Identification',
                    value: employee.nic ?? dash,
                    muted: employee.nic == null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Emergency Contact',
            child: SelloFormRow(
              left: _Field(
                label: 'Contact name',
                value: employee.emergencyContactName ?? dash,
                muted: employee.emergencyContactName == null,
              ),
              right: _Field(
                label: 'Contact phone',
                value:
                    PhoneNumber.displayOrNull(employee.emergencyContactPhone) ??
                    dash,
                muted: employee.emergencyContactPhone == null,
              ),
            ),
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Employment',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(label: 'Role', value: employee.role.name),
                  right: _Field(
                    label: 'Branch',
                    value: employee.branchName ?? dash,
                    muted: employee.branchName == null,
                  ),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'Department',
                    value: employee.department ?? dash,
                    muted: employee.department == null,
                  ),
                  right: _Field(
                    label: 'Joined date',
                    value: SelloFormatters.date(employee.joinedAt),
                    muted: employee.joinedAt == null,
                  ),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'Employment status',
                    value: employee.employmentStatus.label,
                  ),
                  right: _Field(
                    label: 'Last active',
                    value: employee.lastActiveAt == null
                        ? dash
                        : _dateTime.format(employee.lastActiveAt!.toLocal()),
                    muted: employee.lastActiveAt == null,
                  ),
                ),
              ],
            ),
          ),
          if (employee.notes != null && employee.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 28),
            _Section(
              title: 'Notes',
              child: Text(
                employee.notes!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          _Section(
            title: 'Assignments',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (customerAssignments.isEmpty)
                  const Text(
                    'No customer assignments yet. Territories, routes, and '
                    'category assignments are reserved for later.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  for (final assignment in customerAssignments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              assignment.targetLabel ?? 'Customer',
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (onRemoveAssignment != null)
                            TextButton(
                              onPressed: () => onRemoveAssignment!(assignment),
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ),
                if (onAssignCustomer != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelloButton(
                      label: 'Assign customer',
                      variant: SelloButtonVariant.outline,
                      size: SelloButtonSize.small,
                      onPressed: onAssignCustomer,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Access',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.hasLogin
                      ? 'This person can open ${profile.workspace} with ${employee.email}.'
                      : 'Their invitation is pending. Resend so they can get started on ${profile.workspace}.',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (onInvite != null) ...[
                  const SizedBox(height: 12),
                  SelloButton(
                    label: 'Resend invitation',
                    variant: SelloButtonVariant.outline,
                    size: SelloButtonSize.small,
                    onPressed: onInvite,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Role guidance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.guidance,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                for (final cap in profile.capabilities)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cap,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (profile.modules.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'What they can use',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final access in profile.modules)
                        if (access.canView)
                          SelloMetaPill(
                            value:
                                '${access.module.label} · ${_accessLabel(access)}',
                          ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Coming next',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                SelloMetaPill(value: 'Custom roles'),
                SelloMetaPill(value: 'Permission templates'),
                SelloMetaPill(value: 'Temporary access'),
                SelloMetaPill(value: 'Delegation'),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Company activity',
            child: EntityActivityPanel(
              referenceType: 'employee',
              referenceId: employee.id,
              emptyMessage: 'Team activity will appear here.',
            ),
          ),
          const SizedBox(height: 28),
          _Section(
            title: 'Activity',
            child: activity.isEmpty
                ? const Text(
                    'No recorded activity yet. Customer, order, inventory, '
                    'and payment actions will appear here over time.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Column(
                    children: [
                      for (final event in activity.take(20))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.summary,
                                      style: const TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      _dateTime.format(
                                        event.createdAt.toLocal(),
                                      ),
                                      style: const TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel:
            onArchive != null &&
                employee.employmentStatus == EmploymentStatus.active
            ? 'Archive'
            : onRestore != null &&
                  employee.employmentStatus != EmploymentStatus.active
            ? 'Set active'
            : 'Close',
        cancelVariant: SelloButtonVariant.outline,
        onCancel:
            onArchive != null &&
                employee.employmentStatus == EmploymentStatus.active
            ? onArchive
            : onRestore != null &&
                  employee.employmentStatus != EmploymentStatus.active
            ? onRestore
            : () => Navigator.of(context).maybePop(),
        primaryLabel: onEdit != null ? 'Edit employee' : 'Close',
        onPrimary: onEdit ?? () => Navigator.of(context).maybePop(),
      ),
    );
  }

  static SelloStatusTone _statusTone(EmploymentStatus status) =>
      switch (status) {
        EmploymentStatus.active => SelloStatusTone.success,
        EmploymentStatus.inactive => SelloStatusTone.neutral,
        EmploymentStatus.suspended => SelloStatusTone.warning,
        EmploymentStatus.archived => SelloStatusTone.danger,
      };
}

String _accessLabel(ModuleAccess access) {
  if (access.canApprove && access.canManage) return 'full';
  if (access.canManage) return 'manage';
  return 'view';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: muted ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
