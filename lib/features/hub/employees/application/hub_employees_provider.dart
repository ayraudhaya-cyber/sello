import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/employee_repository.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/branch.dart';
import 'package:sello/shared/models/employee_activity_event.dart';
import 'package:sello/shared/models/employee_assignment.dart';
import 'package:sello/shared/models/employee_summary.dart';
import 'package:sello/shared/models/employee_upsert_input.dart';
import 'package:sello/shared/models/employment_status.dart';
import 'package:sello/shared/models/role.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/models/team_invite_result.dart';

enum EmployeeStatusFilter { all, active, inactive, suspended, archived }

enum EmployeeRoleFilter {
  all,
  owner,
  manager,
  salesRepresentative,
}

extension on EmployeeRoleFilter {
  String? get roleCode => switch (this) {
        EmployeeRoleFilter.all => null,
        EmployeeRoleFilter.owner => 'owner',
        EmployeeRoleFilter.manager => 'manager',
        EmployeeRoleFilter.salesRepresentative => 'sales_representative',
      };
}

extension on EmployeeStatusFilter {
  EmploymentStatus? get status => switch (this) {
        EmployeeStatusFilter.all => null,
        EmployeeStatusFilter.active => EmploymentStatus.active,
        EmployeeStatusFilter.inactive => EmploymentStatus.inactive,
        EmployeeStatusFilter.suspended => EmploymentStatus.suspended,
        EmployeeStatusFilter.archived => EmploymentStatus.archived,
      };
}

class HubEmployeesState {
  const HubEmployeesState({
    this.items = const [],
    this.roles = const [],
    this.branches = const [],
    this.stats = const EmployeeDashboardStats(),
    this.search = '',
    this.statusFilter = EmployeeStatusFilter.all,
    this.roleFilter = EmployeeRoleFilter.all,
    this.branchId,
    this.page = 0,
    this.pageSize = 20,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<EmployeeSummary> items;
  final List<Role> roles;
  final List<Branch> branches;
  final EmployeeDashboardStats stats;
  final String search;
  final EmployeeStatusFilter statusFilter;
  final EmployeeRoleFilter roleFilter;

  /// null = all branches.
  final String? branchId;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  HubEmployeesState copyWith({
    List<EmployeeSummary>? items,
    List<Role>? roles,
    List<Branch>? branches,
    EmployeeDashboardStats? stats,
    String? search,
    EmployeeStatusFilter? statusFilter,
    EmployeeRoleFilter? roleFilter,
    String? branchId,
    bool clearBranch = false,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubEmployeesState(
      items: items ?? this.items,
      roles: roles ?? this.roles,
      branches: branches ?? this.branches,
      stats: stats ?? this.stats,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      roleFilter: roleFilter ?? this.roleFilter,
      branchId: clearBranch ? null : (branchId ?? this.branchId),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

class HubEmployeesNotifier extends Notifier<HubEmployeesState> {
  EmployeeRepository get _repo => ref.read(employeeRepositoryProvider);

  @override
  HubEmployeesState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(_initialize);
    return const HubEmployeesState(isLoading: true);
  }

  Future<void> _initialize() async {
    final session = ref.read(currentSessionProvider);
    try {
      final roles = await _repo.fetchAssignableRoles();
      state = state.copyWith(roles: roles);
    } catch (_) {}
    if (session != null) {
      try {
        final branches = await ref
            .read(branchRepositoryProvider)
            .fetchBranches(companyId: session.company.id);
        state = state.copyWith(branches: branches);
      } catch (_) {}
    }
    await refresh();
  }

  Future<void> refresh() => loadEmployees(resetPage: true);

  Future<void> loadEmployees({
    bool resetPage = false,
    bool showLoading = true,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      state = state.copyWith(
        items: const [],
        isLoading: false,
        initialized: true,
        errorMessage: 'Sign in required.',
      );
      return;
    }

    final page = resetPage ? 0 : state.page;
    state = state.copyWith(
      isLoading: showLoading ? true : state.isLoading,
      page: page,
      clearError: true,
    );

    try {
      final companyId = session.company.id;
      final result = await _repo.fetchEmployees(
        companyId: companyId,
        search: state.search,
        roleCode: state.roleFilter.roleCode,
        status: state.statusFilter.status,
        branchId: state.branchId,
        page: page,
        pageSize: state.pageSize,
      );
      final stats = await _repo.fetchDashboardStats(companyId: companyId);

      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        stats: stats,
        isLoading: false,
        initialized: true,
      );
    } on AppFailure catch (e) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        errorMessage: 'Unable to load employees.',
      );
    }
  }

  void setSearch(String value) {
    if (state.search == value) return;
    state = state.copyWith(search: value);
    loadEmployees(resetPage: true, showLoading: false);
  }

  void setStatusFilter(EmployeeStatusFilter filter) {
    if (state.statusFilter == filter) return;
    state = state.copyWith(statusFilter: filter);
    loadEmployees(resetPage: true);
  }

  void setRoleFilter(EmployeeRoleFilter filter) {
    if (state.roleFilter == filter) return;
    state = state.copyWith(roleFilter: filter);
    loadEmployees(resetPage: true);
  }

  void setBranchFilter(String? branchId) {
    state = state.copyWith(
      branchId: branchId,
      clearBranch: branchId == null,
    );
    loadEmployees(resetPage: true);
  }

  void goToPage(int page) {
    if (page < 0 || page == state.page) return;
    state = state.copyWith(page: page);
    loadEmployees();
  }

  /// Returns null on success, or an error message.
  ///
  /// [onInvite] is called after a successful create with the invitation
  /// delivery outcome (for owner-friendly toasts).
  Future<String?> saveEmployee(
    EmployeeUpsertInput input, {
    void Function(TeamInviteResult invite)? onInvite,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      ref.read(permissionServiceProvider)?.require(
            AppModule.employees,
            input.isCreate ? PermissionAction.create : PermissionAction.edit,
          );
      final result = await _repo.upsertEmployee(
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        input: input,
      );
      state = state.copyWith(isSaving: false);
      await loadEmployees(resetPage: input.isCreate, showLoading: false);
      final invite = result.invite;
      if (invite != null) onInvite?.call(invite);
      return null;
    } on AppFailure catch (e) {
      state = state.copyWith(isSaving: false);
      return e.message;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return 'Unable to save team member.';
    }
  }

  Future<String?> setStatus(
    EmployeeSummary employee, {
    required EmploymentStatus status,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';
    if (employee.id == session.employee.id &&
        status != EmploymentStatus.active) {
      return 'You cannot deactivate your own account.';
    }

    state = state.copyWith(isSaving: true);
    try {
      await _repo.setEmploymentStatus(
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        employeeId: employee.id,
        status: status,
      );
      state = state.copyWith(isSaving: false);
      await loadEmployees(showLoading: false);
      return null;
    } on AppFailure catch (e) {
      state = state.copyWith(isSaving: false);
      return e.message;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return 'Unable to update status.';
    }
  }

  Future<List<EmployeeActivityEvent>> loadActivity(EmployeeSummary employee) {
    final session = ref.read(currentSessionProvider);
    if (session == null) return Future.value(const []);
    return _repo.fetchActivity(
      companyId: session.company.id,
      employeeId: employee.id,
    );
  }

  Future<List<EmployeeAssignment>> loadAssignments(EmployeeSummary employee) {
    final session = ref.read(currentSessionProvider);
    if (session == null) return Future.value(const []);
    return _repo.fetchAssignments(
      companyId: session.company.id,
      employeeId: employee.id,
    );
  }

  Future<String?> sendLoginInvite(
    EmployeeSummary employee, {
    void Function(TeamInviteResult invite)? onInvite,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';
    state = state.copyWith(isSaving: true);
    try {
      final invite = await _repo.sendLoginInvite(
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        employeeId: employee.id,
      );
      state = state.copyWith(isSaving: false);
      await loadEmployees(showLoading: false);
      onInvite?.call(invite);
      return null;
    } on AppFailure catch (e) {
      state = state.copyWith(isSaving: false);
      return e.message;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return 'Unable to send invitation.';
    }
  }

  Future<String?> assignCustomer({
    required EmployeeSummary employee,
    required String customerId,
    required String customerName,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';
    try {
      await _repo.assignCustomer(
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        employeeId: employee.id,
        customerId: customerId,
        customerName: customerName,
      );
      await loadEmployees(showLoading: false);
      return null;
    } on AppFailure catch (e) {
      return e.message;
    } catch (_) {
      return 'Unable to assign customer.';
    }
  }

  Future<String?> removeAssignment({
    required EmployeeSummary employee,
    required String assignmentId,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';
    try {
      await _repo.removeAssignment(
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        assignmentId: assignmentId,
        employeeId: employee.id,
      );
      await loadEmployees(showLoading: false);
      return null;
    } on AppFailure catch (e) {
      return e.message;
    } catch (_) {
      return 'Unable to remove assignment.';
    }
  }
}

final hubEmployeesProvider =
    NotifierProvider<HubEmployeesNotifier, HubEmployeesState>(
  HubEmployeesNotifier.new,
);
