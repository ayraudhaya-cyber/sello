import 'dart:typed_data';

import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/employees/employee_login_invite_response.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/branch.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/employee_activity_event.dart';
import 'package:sello/shared/models/employee_assignment.dart';
import 'package:sello/shared/models/employee_summary.dart';
import 'package:sello/shared/models/employee_upsert_input.dart';
import 'package:sello/shared/models/employment_status.dart';
import 'package:sello/shared/models/role.dart';
import 'package:sello/shared/models/team_invite_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Aggregate loaded for [AppSession] construction.
class EmployeeContext {
  const EmployeeContext({
    required this.employee,
    required this.company,
    required this.role,
    this.branch,
  });

  final Employee employee;
  final Company company;
  final Role role;
  final Branch? branch;
}

/// Shared people / identity repository for Hub and future Sales.
class EmployeeRepository {
  EmployeeRepository({
    SupabaseClient? client,
    MediaStorageService? imageStorage,
    MediaService? media,
    BusinessEventBus? events,
  })  : _client = client ?? SupabaseService.client,
        _imageStorage = imageStorage ?? MediaStorageService(),
        _media = media ?? MediaService(),
        _events = events ?? BusinessEventBus();

  final SupabaseClient _client;
  final MediaStorageService _imageStorage;
  final MediaService _media;
  final BusinessEventBus _events;

  static const _employeeSelect = '''
    id,
    company_id,
    branch_id,
    role_id,
    user_id,
    email,
    full_name,
    phone,
    avatar_url,
    employee_code,
    employment_status,
    is_active,
    deleted_at,
    roles!employees_role_id_fkey (
      id,
      code,
      name,
      description,
      display_order
    ),
    companies!employees_company_id_fkey (
      id,
      name,
      legal_name,
      company_code,
      slug,
      is_active,
      plan,
      subscription_status,
      activated_at,
      expires_at,
      deleted_at
    ),
    branches!employees_branch_id_fkey (
      id,
      company_id,
      name,
      code,
      phone,
      email,
      manager_name,
      is_active,
      deleted_at
    )
  ''';

  static const _directorySelect = '''
    id,
    company_id,
    branch_id,
    role_id,
    user_id,
    email,
    full_name,
    phone,
    avatar_url,
    employee_code,
    nic,
    address,
    emergency_contact_name,
    emergency_contact_phone,
    department,
    joined_at,
    employment_status,
    last_active_at,
    sales_territory,
    notes,
    is_active,
    created_at,
    updated_at,
    deleted_at,
    roles!employees_role_id_fkey (
      id,
      code,
      name,
      description,
      display_order
    ),
    branches!employees_branch_id_fkey (
      id,
      name
    )
  ''';

  /// Fetches the active employee for an authenticated user.
  Future<EmployeeContext> fetchContextByUserId(
    String userId, {
    String? email,
  }) async {
    try {
      final authUserId = userId.trim();
      if (authUserId.isEmpty) {
        throw const AuthFailure('Missing authenticated user id.');
      }

      var row = await _fetchByUserId(authUserId);

      if (row == null) {
        final fallbackEmail = email?.trim();
        if (fallbackEmail != null && fallbackEmail.isNotEmpty) {
          row = await _fetchByEmail(fallbackEmail);
          // Persist Auth link so future sessions resolve by user_id.
          if (row != null &&
              (row['user_id'] == null ||
                  (row['user_id'] as String?)?.isEmpty == true)) {
            try {
              final employeeId = row['id'] as String?;
              if (employeeId != null) {
                await _client.from('employees').update({
                  'user_id': authUserId,
                }).eq('id', employeeId);
                row = {
                  ...row,
                  'user_id': authUserId,
                };
              }
            } catch (_) {
              // RLS may block self-link; session can still proceed via email.
            }
          }
        }
      }

      if (row == null) {
        throw const UnlinkedEmployeeFailure();
      }

      if (row['deleted_at'] != null) {
        throw const AuthFailure(
          'This account has been deactivated. Contact your administrator.',
        );
      }

      final employee = Employee.fromJson(row);
      if (!employee.isActive ||
          !employee.employmentStatus.canAuthenticate) {
        throw const AuthFailure(
          'This account is inactive. Contact your administrator.',
        );
      }

      final roleJson = row['roles'];
      final companyJson = row['companies'];
      if (roleJson is! Map<String, dynamic>) {
        throw const AuthFailure('Employee role could not be loaded.');
      }
      if (companyJson is! Map<String, dynamic>) {
        throw const AuthFailure('Employee company could not be loaded.');
      }

      final company = Company.fromJson(companyJson);
      if (!company.isActive || companyJson['deleted_at'] != null) {
        throw const AuthFailure(
          'Your company account is inactive. Contact support.',
        );
      }

      final role = Role.fromJson(roleJson);

      Branch? branch;
      final branchJson = row['branches'];
      if (branchJson is Map<String, dynamic> &&
          branchJson['deleted_at'] == null) {
        branch = Branch.fromJson(branchJson);
      }

      return EmployeeContext(
        employee: employee,
        company: company,
        role: role,
        branch: branch,
      );
    } on UnlinkedEmployeeFailure {
      rethrow;
    } on AuthFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw AuthFailure(
        error.message.trim().isEmpty
            ? 'Unable to load your profile. Please try again.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure(
        'Unable to load your profile. Please try again.',
      );
    }
  }

  Future<List<Role>> fetchAssignableRoles() async {
    try {
      final rows = await _client
          .from('roles')
          .select('id, code, name, description, display_order')
          .inFilter('code', const [
            'owner',
            'manager',
            'sales_representative',
          ])
          .order('display_order');
      return (rows as List)
          .map((e) => Role.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load roles.');
    }
  }

  Future<EmployeeDashboardStats> fetchDashboardStats({
    required String companyId,
  }) async {
    try {
      final rows = await _client
          .from('employees')
          .select(
            'employment_status, roles!employees_role_id_fkey(code)',
          )
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);

      var total = 0;
      var active = 0;
      var salesRepresentatives = 0;
      var managers = 0;
      var inactive = 0;

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        total++;
        final status =
            EmploymentStatus.fromCode(row['employment_status'] as String?);
        if (status == EmploymentStatus.active) {
          active++;
        } else {
          inactive++;
        }
        final roleJson = row['roles'];
        final code = roleJson is Map
            ? (roleJson['code'] as String? ?? '')
            : '';
        if (code == 'sales_representative') salesRepresentatives++;
        if (code == 'manager') managers++;
      }

      return EmployeeDashboardStats(
        total: total,
        active: active,
        salesRepresentatives: salesRepresentatives,
        managers: managers,
        inactive: inactive,
      );
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load employee stats.');
    }
  }

  Future<({List<EmployeeSummary> items, bool hasMore})> fetchEmployees({
    required String companyId,
    String search = '',
    String? roleCode,
    EmploymentStatus? status,
    String? branchId,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      String? roleId;
      final code = roleCode?.trim();
      if (code != null && code.isNotEmpty) {
        final roleRow = await _client
            .from('roles')
            .select('id')
            .eq('code', code)
            .maybeSingle();
        if (roleRow == null) {
          return (items: <EmployeeSummary>[], hasMore: false);
        }
        roleId = roleRow['id'] as String;
      }

      var query = _client
          .from('employees')
          .select(_directorySelect)
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);

      if (status != null) {
        query = query.eq('employment_status', status.code);
      }
      if (roleId != null) {
        query = query.eq('role_id', roleId);
      }
      if (branchId != null && branchId.isNotEmpty) {
        query = query.eq('branch_id', branchId);
      }

      final trimmed = search.trim();
      if (trimmed.isNotEmpty) {
        final escaped = trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_');
        query = query.or(
          'full_name.ilike.%$escaped%,'
          'email.ilike.%$escaped%,'
          'phone.ilike.%$escaped%,'
          'employee_code.ilike.%$escaped%',
        );
      }

      final from = page * pageSize;
      final to = from + pageSize;
      final rows = await query.order('full_name').range(from, to);

      var items = (rows as List)
          .map(
            (e) =>
                EmployeeSummary.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();

      final hasMore = items.length > pageSize;
      if (hasMore) {
        items = items.sublist(0, pageSize);
      }

      items = await _attachAvatarsAndAssignments(companyId, items);

      return (items: items, hasMore: hasMore);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load employees.');
    }
  }

  /// Finds an active employee by email within a company (for retry safety).
  Future<EmployeeSummary?> findEmployeeByEmail({
    required String companyId,
    required String email,
  }) async {
    try {
      final row = await _client
          .from('employees')
          .select(_directorySelect)
          .eq('company_id', companyId)
          .eq('email', email.trim().toLowerCase())
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return EmployeeSummary.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  Future<EmployeeSummary?> fetchEmployeeById({
    required String companyId,
    required String employeeId,
  }) async {
    try {
      final row = await _client
          .from('employees')
          .select(_directorySelect)
          .eq('company_id', companyId)
          .eq('id', employeeId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      final summary =
          EmployeeSummary.fromJson(Map<String, dynamic>.from(row));
      final enriched =
          await _attachAvatarsAndAssignments(companyId, [summary]);
      return enriched.first;
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load employee.');
    }
  }

  Future<List<EmployeeActivityEvent>> fetchActivity({
    required String companyId,
    required String employeeId,
    int limit = 40,
  }) async {
    try {
      final rows = await _client
          .from('employee_activity_events')
          .select()
          .eq('company_id', companyId)
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map(
            (e) => EmployeeActivityEvent.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load activity.');
    }
  }

  Future<void> logActivity({
    required String employeeId,
    required String eventType,
    required String summary,
    String? referenceType,
    String? referenceId,
  }) async {
    try {
      await _client.rpc(
        'log_employee_activity',
        params: {
          'p_employee_id': employeeId,
          'p_event_type': eventType,
          'p_summary': summary,
          'p_reference_type': referenceType,
          'p_reference_id': referenceId,
        },
      );
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      // Activity logging must not block primary flows.
    }
  }

  Future<EmployeeUpsertResult> upsertEmployee({
    required String companyId,
    required String actorEmployeeId,
    required EmployeeUpsertInput input,
  }) async {
    try {
      final payload = <String, dynamic>{
        'company_id': companyId,
        'full_name': input.fullName.trim(),
        'email': input.email.trim().toLowerCase(),
        'role_id': input.roleId,
        'employment_status': input.employmentStatus.code,
        'phone': _blankToNull(input.phone),
        'employee_code': _blankToNull(input.employeeCode),
        'nic': _blankToNull(input.nic),
        'address': _blankToNull(input.address),
        'emergency_contact_name': _blankToNull(input.emergencyContactName),
        'emergency_contact_phone': _blankToNull(input.emergencyContactPhone),
        'department': _blankToNull(input.department),
        'joined_at': input.joinedAt?.toIso8601String().split('T').first,
        'branch_id': _blankToNull(input.branchId),
        'sales_territory': _blankToNull(input.salesTerritory),
        'notes': _blankToNull(input.notes),
        'updated_by': actorEmployeeId,
      };

      String employeeId;
      if (input.isCreate) {
        payload['created_by'] = actorEmployeeId;
        if (payload['employee_code'] == null) {
          payload['employee_code'] =
              await _nextEmployeeCode(companyId: companyId);
        }
        final inserted = await _client
            .from('employees')
            .insert(payload)
            .select('id')
            .single();
        employeeId = inserted['id'] as String;
      } else {
        employeeId = input.id!;
        await _client
            .from('employees')
            .update(payload)
            .eq('id', employeeId)
            .eq('company_id', companyId);
      }

      if (input.clearAvatar) {
        await _clearAvatar(
          companyId: companyId,
          employeeId: employeeId,
          actorEmployeeId: actorEmployeeId,
        );
      } else if (input.avatarBytes != null && input.avatarBytes!.isNotEmpty) {
        await _uploadAvatar(
          companyId: companyId,
          employeeId: employeeId,
          actorEmployeeId: actorEmployeeId,
          bytes: input.avatarBytes!,
        );
      }

      await logActivity(
        employeeId: actorEmployeeId,
        eventType: input.isCreate ? 'employee_created' : 'employee_updated',
        summary: input.isCreate
            ? 'Added team member ${input.fullName.trim()}'
            : 'Updated team member ${input.fullName.trim()}',
        referenceType: 'employee',
        referenceId: employeeId,
      );

      TeamInviteResult? invite;
      if (input.isCreate) {
        invite = await sendLoginInvite(
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          employeeId: employeeId,
        );

        await _events.publish(
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          event: BusinessEvents.teamMemberJoined(
            employeeId: employeeId,
            fullName: input.fullName.trim(),
            excludeEmployeeId: employeeId,
          ),
        );
      }

      final saved = await fetchEmployeeById(
        companyId: companyId,
        employeeId: employeeId,
      );
      if (saved == null) {
        throw const UnexpectedFailure(
          'Team member saved but could not reload.',
        );
      }
      return EmployeeUpsertResult(employee: saved, invite: invite);
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to save team member.');
    }
  }

  /// Provisions Sello access via the `invite-employee-login` Edge Function.
  ///
  /// Auth user creation and the password-setup email run server-side with the
  /// service role so the Owner's browser session is never touched.
  ///
  /// Returns whether the account is ready and whether the email was delivered.
  /// When email delivery fails (e.g. SMTP not configured), the account still
  /// remains linked so the owner can resend later.
  Future<TeamInviteResult> sendLoginInvite({
    required String companyId,
    required String actorEmployeeId,
    required String employeeId,
  }) async {
    try {
      final existing = await fetchEmployeeById(
        companyId: companyId,
        employeeId: employeeId,
      );
      if (existing == null) {
        throw const ValidationFailure('Team member not found.');
      }
      if (existing.employmentStatus != EmploymentStatus.active) {
        throw const ValidationFailure(
          'Only active team members can receive an invitation.',
        );
      }

      final body = <String, dynamic>{
        'employee_id': employeeId,
      };
      final redirectTo =
          EmployeeLoginInviteResponse.redirectToForCurrentOrigin();
      if (redirectTo != null) {
        body['redirect_to'] = redirectTo;
      }

      final response = await _client.functions.invoke(
        EmployeeLoginInviteResponse.functionName,
        body: body,
      );
      final data = EmployeeLoginInviteResponse.asMap(response.data);
      final invite = data == null
          ? null
          : EmployeeLoginInviteResponse.tryParseSuccess(data);

      if (invite == null) {
        final reason = data?['reason']?.toString() ?? 'unknown';
        throw AuthFailure(
          EmployeeLoginInviteResponse.failureMessage(data) +
              (reason != 'unknown' ? ' ($reason)' : ''),
        );
      }

      await logActivity(
        employeeId: actorEmployeeId,
        eventType: 'employee_invited',
        summary: invite.emailDelivered
            ? 'Sent invitation to ${existing.fullName}'
            : 'Prepared access for ${existing.fullName} (invitation email unavailable)',
        referenceType: 'employee',
        referenceId: employeeId,
      );

      await _events.publish(
        companyId: companyId,
        actorEmployeeId: actorEmployeeId,
        event: BusinessEvents.teamMemberInvited(
          employeeId: employeeId,
          fullName: existing.fullName,
          summary: invite.emailDelivered
              ? 'Invitation sent to ${existing.fullName}'
              : 'Access prepared for ${existing.fullName}',
          excludeEmployeeId: actorEmployeeId,
        ),
      );

      return invite;
    } on AppFailure {
      rethrow;
    } on FunctionException catch (error) {
      // ignore: avoid_print
      print('[invite-employee-login] FunctionException: '
          'status=${error.status} '
          'details=${error.details} '
          'reason=${error.reasonPhrase}');
      final data = EmployeeLoginInviteResponse.asMap(error.details) ??
          EmployeeLoginInviteResponse.asMap(error.reasonPhrase);
      throw AuthFailure(EmployeeLoginInviteResponse.failureMessage(data));
    } on PostgrestException catch (e) {
      final message = e.message.trim();
      throw UnexpectedFailure(
        message.isEmpty ? 'Request failed.' : message,
      );
    } catch (error) {
      // ignore: avoid_print
      print('[invite-employee-login] Unexpected: ${error.runtimeType}: $error');
      throw const UnexpectedFailure('Unable to send invitation.');
    }
  }

  Future<List<EmployeeAssignment>> fetchAssignments({
    required String companyId,
    required String employeeId,
  }) async {
    try {
      final rows = await _client
          .from('employee_assignments')
          .select(
            'id, company_id, employee_id, assignment_type, target_id, '
            'target_label, created_at',
          )
          .eq('company_id', companyId)
          .eq('employee_id', employeeId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      return (rows as List)
          .map(
            (row) => EmployeeAssignment.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load assignments.');
    }
  }

  /// Primary sales assignee for a customer (first active assignment).
  Future<({String? employeeId, String? employeeName})> fetchCustomerAssignee({
    required String companyId,
    required String customerId,
  }) async {
    try {
      final row = await _client
          .from('employee_assignments')
          .select(
            'employee_id, employees!employee_id (id, full_name)',
          )
          .eq('company_id', companyId)
          .eq('assignment_type', EmployeeAssignmentType.customer.dbValue)
          .eq('target_id', customerId)
          .isFilter('deleted_at', null)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      if (row == null) {
        return (employeeId: null, employeeName: null);
      }
      final employee = row['employees'];
      return (
        employeeId: row['employee_id'] as String?,
        employeeName:
            employee is Map ? employee['full_name'] as String? : null,
      );
    } catch (_) {
      return (employeeId: null, employeeName: null);
    }
  }

  Future<EmployeeAssignment> assignCustomer({
    required String companyId,
    required String actorEmployeeId,
    required String employeeId,
    required String customerId,
    required String customerName,
  }) async {
    try {
      final existing = await _client
          .from('employee_assignments')
          .select('id')
          .eq('company_id', companyId)
          .eq('employee_id', employeeId)
          .eq('assignment_type', EmployeeAssignmentType.customer.dbValue)
          .eq('target_id', customerId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (existing != null) {
        throw const ValidationFailure('Customer is already assigned.');
      }

      final inserted = await _client
          .from('employee_assignments')
          .insert({
            'company_id': companyId,
            'employee_id': employeeId,
            'assignment_type': EmployeeAssignmentType.customer.dbValue,
            'target_id': customerId,
            'target_label': customerName.trim(),
            'created_by': actorEmployeeId,
            'updated_by': actorEmployeeId,
          })
          .select(
            'id, company_id, employee_id, assignment_type, target_id, '
            'target_label, created_at',
          )
          .single();

      await logActivity(
        employeeId: actorEmployeeId,
        eventType: 'assignment_added',
        summary: 'Assigned customer $customerName',
        referenceType: 'employee',
        referenceId: employeeId,
      );

      return EmployeeAssignment.fromJson(Map<String, dynamic>.from(inserted));
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to assign customer.');
    }
  }

  Future<void> removeAssignment({
    required String companyId,
    required String actorEmployeeId,
    required String assignmentId,
    required String employeeId,
  }) async {
    try {
      await _client.from('employee_assignments').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': actorEmployeeId,
      }).eq('id', assignmentId).eq('company_id', companyId);

      await logActivity(
        employeeId: actorEmployeeId,
        eventType: 'assignment_removed',
        summary: 'Removed an assignment',
        referenceType: 'employee',
        referenceId: employeeId,
      );
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to remove assignment.');
    }
  }

  Future<void> setEmploymentStatus({
    required String companyId,
    required String actorEmployeeId,
    required String employeeId,
    required EmploymentStatus status,
  }) async {
    try {
      await _client.from('employees').update({
        'employment_status': status.code,
        'updated_by': actorEmployeeId,
      }).eq('id', employeeId).eq('company_id', companyId);

      await logActivity(
        employeeId: actorEmployeeId,
        eventType: 'employee_status_changed',
        summary: 'Set employment status to ${status.label}',
        referenceType: 'employee',
        referenceId: employeeId,
      );
    } on PostgrestException catch (e) {
      throw UnexpectedFailure(
        e.message.trim().isEmpty ? 'Request failed.' : e.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to update employee status.');
    }
  }

  Future<Map<String, dynamic>?> _fetchByUserId(String authUserId) async {
    final response = await _client
        .from('employees')
        .select(_employeeSelect)
        .eq('user_id', authUserId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> _fetchByEmail(String email) async {
    final response = await _client
        .from('employees')
        .select(_employeeSelect)
        .eq('email', email)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<List<EmployeeSummary>> _attachAvatarsAndAssignments(
    String companyId,
    List<EmployeeSummary> items,
  ) async {
    if (items.isEmpty) return items;

    final counts = <String, int>{};
    try {
      final assignmentRows = await _client
          .from('employee_assignments')
          .select('employee_id')
          .eq('company_id', companyId)
          .eq('assignment_type', 'customer')
          .isFilter('deleted_at', null);
      for (final raw in assignmentRows as List) {
        final id = (raw as Map)['employee_id'] as String?;
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
    } catch (_) {
      // Assignments table may be empty / unavailable — counts stay 0.
    }

    final result = <EmployeeSummary>[];
    for (final item in items) {
      String? signed = item.avatarUrl;
      final path = item.avatarStoragePath;
      if (path != null && path.isNotEmpty) {
        try {
          signed = await _imageStorage.signEmployeeAvatar(path);
        } catch (_) {
          signed = null;
        }
      }
      result.add(
        item.copyWith(
          avatarUrl: signed,
          assignedCustomerCount: counts[item.id] ?? item.assignedCustomerCount,
        ),
      );
    }
    return result;
  }

  Future<String> _nextEmployeeCode({required String companyId}) async {
    final rows = await _client
        .from('employees')
        .select('employee_code')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null);
    var maxNum = 0;
    for (final raw in rows as List) {
      final code = (raw as Map)['employee_code'] as String?;
      if (code == null) continue;
      final match = RegExp(r'(\d+)\s*$').firstMatch(code);
      if (match == null) continue;
      final n = int.tryParse(match.group(1)!) ?? 0;
      if (n > maxNum) maxNum = n;
    }
    return 'EMP-${(maxNum + 1).toString().padLeft(4, '0')}';
  }

  Future<void> _uploadAvatar({
    required String companyId,
    required String employeeId,
    required String actorEmployeeId,
    required Uint8List bytes,
  }) async {
    final processed = await _media.compressImage(bytes);
    final path =
        '$companyId/$employeeId/avatar.${MediaConstants.jpegExtension}';
    await _imageStorage.uploadEmployeeAvatar(
      path: path,
      bytes: processed.bytes,
      contentType: MediaConstants.jpegContentType,
    );
    await _client.from('employees').update({
      'avatar_url': path,
      'updated_by': actorEmployeeId,
    }).eq('id', employeeId).eq('company_id', companyId);
  }

  Future<void> _clearAvatar({
    required String companyId,
    required String employeeId,
    required String actorEmployeeId,
  }) async {
    final row = await _client
        .from('employees')
        .select('avatar_url')
        .eq('id', employeeId)
        .eq('company_id', companyId)
        .maybeSingle();
    final path = row?['avatar_url'] as String?;
    if (path != null &&
        path.isNotEmpty &&
        !path.startsWith('http')) {
      try {
        await _imageStorage.deleteEmployeeAvatar(path);
      } catch (_) {}
    }
    await _client.from('employees').update({
      'avatar_url': null,
      'updated_by': actorEmployeeId,
    }).eq('id', employeeId).eq('company_id', companyId);
  }

  String? _blankToNull(String? value) {
    final t = value?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}
