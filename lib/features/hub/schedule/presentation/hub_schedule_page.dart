import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/schedule/application/hub_schedule_provider.dart';
import 'package:sello/features/hub/schedule/presentation/plan_route_dialog.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/scheduled_visit.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/quick_new_query.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubSchedulePage extends ConsumerStatefulWidget {
  const HubSchedulePage({super.key});

  @override
  ConsumerState<HubSchedulePage> createState() => _HubSchedulePageState();
}

class _HubSchedulePageState extends ConsumerState<HubSchedulePage>
    with QuickNewQueryMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    consumeQuickNewQuery(
      cleanPath: RoutePaths.hubSchedule,
      open: () => _openEditor(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor({ScheduledVisit? visit}) async {
    await ref.read(hubScheduleProvider.notifier).loadReps();
    if (!mounted) return;
    final state = ref.read(hubScheduleProvider);

    if (visit != null) {
      final result = await showDialog<VisitUpsertInput>(
        context: context,
        barrierDismissible: false,
        builder: (context) => EditVisitDialog(
          visit: visit,
          reps: state.reps,
        ),
      );
      if (result == null) return;
      final error =
          await ref.read(hubScheduleProvider.notifier).saveVisit(result);
      if (!mounted) return;
      if (error != null) {
        SelloSnackbars.error(context, error);
      } else {
        SelloSnackbars.success(context, 'Visit updated.');
      }
      return;
    }

    final planned = await showDialog<List<VisitUpsertInput>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PlanRouteDialog(
        reps: state.reps,
        initialDate: state.day,
      ),
    );
    if (planned == null || planned.isEmpty) return;

    final error =
        await ref.read(hubScheduleProvider.notifier).saveVisits(planned);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      final customerStops =
          planned.where((p) => p.customerId != null).length;
      final areaOnly = customerStops == 0 &&
          planned.any((p) => p.area != null && p.area!.trim().isNotEmpty);
      SelloSnackbars.success(
        context,
        areaOnly
            ? 'Area planned.'
            : customerStops == 1
                ? '1 stop planned.'
                : '$customerStops stops planned.',
      );
    }
  }

  Future<void> _setStatus(ScheduledVisit visit, VisitStatus status) async {
    final error = await ref.read(hubScheduleProvider.notifier).setStatus(
          visitId: visit.id,
          status: status,
        );
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Marked ${status.label.toLowerCase()}.');
    }
  }

  Future<void> _remove(ScheduledVisit visit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove visit?'),
        content: Text(
          'Remove ${visit.displayTitle}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error =
        await ref.read(hubScheduleProvider.notifier).removeVisit(visit.id);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Visit removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubScheduleProvider);

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Schedule',
      subtitle:
          'Plan customer visits for your sales team — day, week, and route-ready.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScheduleToolbar(
            searchController: _searchController,
            state: state,
            onSearchChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () =>
                    ref.read(hubScheduleProvider.notifier).setSearch(value),
              );
            },
            onViewChanged: (mode) {
              if (mode != null) {
                ref.read(hubScheduleProvider.notifier).setViewMode(mode);
              }
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref
                    .read(hubScheduleProvider.notifier)
                    .setStatusFilter(value);
              }
            },
            onRepChanged: (value) {
              ref
                  .read(hubScheduleProvider.notifier)
                  .setEmployeeFilter(value == _allReps ? null : value);
            },
            onPrev: () =>
                ref.read(hubScheduleProvider.notifier).shiftFocus(-1),
            onNext: () =>
                ref.read(hubScheduleProvider.notifier).shiftFocus(1),
            onToday: () => ref
                .read(hubScheduleProvider.notifier)
                .setFocusDate(DateTime.now()),
            onPickDate: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: state.day,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                ref.read(hubScheduleProvider.notifier).setFocusDate(picked);
              }
            },
            onRefresh: state.isLoading
                ? null
                : () => ref.read(hubScheduleProvider.notifier).refresh(),
            onSchedule: state.isSaving ? null : () => _openEditor(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.isLoading && state.items.isEmpty)
            const SelloListSkeleton()
          else ...[
            _ScheduleSummaryRow(stats: state.stats),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load schedule',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubScheduleProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              SelloCard(
                child: SelloEmptyState(
                  title: 'No visits in this range',
                  message:
                      'Schedule a customer visit for a sales representative. '
                      'Today’s stops appear automatically on their Home screen.',
                  icon: Icons.calendar_month_rounded,
                  actionLabel: 'Schedule Visit',
                  onAction: () => _openEditor(),
                ),
              )
            else
              SelloFadeIn(
                child: switch (state.viewMode) {
                  ScheduleViewMode.day => _DayView(
                      day: state.day,
                      visits: state.items,
                      onEdit: (v) => _openEditor(visit: v),
                      onStatus: _setStatus,
                      onRemove: _remove,
                    ),
                  ScheduleViewMode.week => _WeekView(
                      focus: state.day,
                      visits: state.items,
                      onSelectDay: (d) => ref
                          .read(hubScheduleProvider.notifier)
                          .setFocusDate(d),
                      onEdit: (v) => _openEditor(visit: v),
                      onStatus: _setStatus,
                      onRemove: _remove,
                    ),
                  ScheduleViewMode.calendar => _CalendarView(
                      focus: state.day,
                      visits: state.items,
                      onSelectDay: (d) {
                        ref
                            .read(hubScheduleProvider.notifier)
                            .setFocusDate(d);
                        ref
                            .read(hubScheduleProvider.notifier)
                            .setViewMode(ScheduleViewMode.day);
                      },
                    ),
                  ScheduleViewMode.list => _ListView(
                      visits: state.items,
                      onEdit: (v) => _openEditor(visit: v),
                      onStatus: _setStatus,
                      onRemove: _remove,
                    ),
                },
              ),
          ],
        ],
      ),
    );
  }
}

const _allReps = '__all_reps__';

class _ScheduleToolbar extends StatelessWidget {
  const _ScheduleToolbar({
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onViewChanged,
    required this.onStatusChanged,
    required this.onRepChanged,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onPickDate,
    required this.onRefresh,
    required this.onSchedule,
  });

  final TextEditingController searchController;
  final HubScheduleState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ScheduleViewMode?> onViewChanged;
  final ValueChanged<VisitStatusFilter?> onStatusChanged;
  final ValueChanged<String?> onRepChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onPickDate;
  final VoidCallback? onRefresh;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloListToolbar(
          searchController: searchController,
          onSearchChanged: onSearchChanged,
          searchHint: 'Search customers, reps, purpose…',
          filters: [
            SizedBox(
              width: context.isMobile ? double.infinity : 120,
              child: SelloDropdown<ScheduleViewMode>(
                value: state.viewMode,
                compact: true,
                hint: 'View',
                onChanged: onViewChanged,
                items: const [
                  DropdownMenuItem(
                    value: ScheduleViewMode.day,
                    child: Text('Day'),
                  ),
                  DropdownMenuItem(
                    value: ScheduleViewMode.week,
                    child: Text('Week'),
                  ),
                  DropdownMenuItem(
                    value: ScheduleViewMode.list,
                    child: Text('List'),
                  ),
                  DropdownMenuItem(
                    value: ScheduleViewMode.calendar,
                    child: Text('Calendar'),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: context.isMobile ? double.infinity : 140,
              child: SelloDropdown<VisitStatusFilter>(
                value: state.statusFilter,
                compact: true,
                hint: 'Status',
                onChanged: onStatusChanged,
                items: const [
                  DropdownMenuItem(
                    value: VisitStatusFilter.all,
                    child: Text('All'),
                  ),
                  DropdownMenuItem(
                    value: VisitStatusFilter.scheduled,
                    child: Text('Scheduled'),
                  ),
                  DropdownMenuItem(
                    value: VisitStatusFilter.completed,
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(
                    value: VisitStatusFilter.missed,
                    child: Text('Missed'),
                  ),
                  DropdownMenuItem(
                    value: VisitStatusFilter.cancelled,
                    child: Text('Cancelled'),
                  ),
                  DropdownMenuItem(
                    value: VisitStatusFilter.unplanned,
                    child: Text('Unplanned'),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: context.isMobile ? double.infinity : 160,
              child: SelloDropdown<String>(
                value: state.employeeId ?? _allReps,
                compact: true,
                hint: 'Sales rep',
                onChanged: onRepChanged,
                items: [
                  const DropdownMenuItem(
                    value: _allReps,
                    child: Text('All reps'),
                  ),
                  for (final rep in state.reps)
                    DropdownMenuItem(value: rep.id, child: Text(rep.name)),
                ],
              ),
            ),
          ],
          actions: [
            SelloButton(
              label: 'Plan visits',
              icon: Icons.route_rounded,
              size: SelloButtonSize.small,
              onPressed: onSchedule,
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            TextButton(
              onPressed: onPickDate,
              child: Text(
                _focusLabel(state),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            TextButton(onPressed: onToday, child: const Text('Today')),
          ],
        ),
      ],
    );
  }

  String _focusLabel(HubScheduleState state) {
    final d = state.day;
    return switch (state.viewMode) {
      ScheduleViewMode.day || ScheduleViewMode.list =>
        SelloFormatters.date(d),
      ScheduleViewMode.week => 'Week of ${SelloFormatters.date(
          d.subtract(Duration(days: d.weekday - 1)),
        )}',
      ScheduleViewMode.calendar =>
        '${_monthName(d.month)} ${d.year}',
    };
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

class _ScheduleSummaryRow extends StatelessWidget {
  const _ScheduleSummaryRow({required this.stats});

  final VisitDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      gap: AppSpacing.sm,
      children: [
        SelloStatCard(
          label: 'Today',
          value: '${stats.today}',
          icon: Icons.today_outlined,
          tone: AppColors.ops,
        ),
        SelloStatCard(
          label: 'Scheduled',
          value: '${stats.scheduled}',
          icon: Icons.event_outlined,
          tone: AppColors.info,
        ),
        SelloStatCard(
          label: 'Completed',
          value: '${stats.completed}',
          icon: Icons.check_circle_outline_rounded,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Missed',
          value: '${stats.missed}',
          icon: Icons.event_busy_outlined,
          tone: AppColors.attention,
        ),
      ],
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.day,
    required this.visits,
    required this.onEdit,
    required this.onStatus,
    required this.onRemove,
  });

  final DateTime day;
  final List<ScheduledVisit> visits;
  final ValueChanged<ScheduledVisit> onEdit;
  final void Function(ScheduledVisit, VisitStatus) onStatus;
  final ValueChanged<ScheduledVisit> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${visits.length} visit${visits.length == 1 ? '' : 's'} · ${SelloFormatters.date(day)}',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final visit in visits) ...[
          _VisitCard(
            visit: visit,
            onEdit: () => onEdit(visit),
            onStatus: (s) => onStatus(visit, s),
            onRemove: () => onRemove(visit),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.focus,
    required this.visits,
    required this.onSelectDay,
    required this.onEdit,
    required this.onStatus,
    required this.onRemove,
  });

  final DateTime focus;
  final List<ScheduledVisit> visits;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<ScheduledVisit> onEdit;
  final void Function(ScheduledVisit, VisitStatus) onStatus;
  final ValueChanged<ScheduledVisit> onRemove;

  @override
  Widget build(BuildContext context) {
    final monday = focus.subtract(Duration(days: focus.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    return Column(
      children: [
        for (final day in days) ...[
          _WeekDayBlock(
            day: day,
            isFocus: _sameDay(day, focus),
            visits: visits
                .where((v) => _sameDay(v.visitDate, day))
                .toList(growable: false),
            onSelectDay: onSelectDay,
            onEdit: onEdit,
            onStatus: onStatus,
            onRemove: onRemove,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _WeekDayBlock extends StatelessWidget {
  const _WeekDayBlock({
    required this.day,
    required this.isFocus,
    required this.visits,
    required this.onSelectDay,
    required this.onEdit,
    required this.onStatus,
    required this.onRemove,
  });

  final DateTime day;
  final bool isFocus;
  final List<ScheduledVisit> visits;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<ScheduledVisit> onEdit;
  final void Function(ScheduledVisit, VisitStatus) onStatus;
  final ValueChanged<ScheduledVisit> onRemove;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      onTap: () => onSelectDay(day),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                SelloFormatters.date(day),
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  color: isFocus ? AppColors.ops : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${visits.length}',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (visits.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No visits',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            for (final visit in visits.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => onEdit(visit),
                  child: Text(
                    '${visit.preferredTimeLabel ?? 'Anytime'} · '
                    '${visit.displayTitle} · '
                    '${visit.employeeName ?? 'Rep'}',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            if (visits.length > 4)
              Text(
                '+${visits.length - 4} more',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.focus,
    required this.visits,
    required this.onSelectDay,
  });

  final DateTime focus;
  final List<ScheduledVisit> visits;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(focus.year, focus.month, 1);
    final daysInMonth = DateTime(focus.year, focus.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return SelloCard(
      child: Column(
        children: [
          Row(
            children: [
              for (final label in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: _CalendarCell(
                        dayIndex: r * 7 + c - leading + 1,
                        daysInMonth: daysInMonth,
                        focus: focus,
                        visits: visits,
                        onSelectDay: onSelectDay,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.dayIndex,
    required this.daysInMonth,
    required this.focus,
    required this.visits,
    required this.onSelectDay,
  });

  final int dayIndex;
  final int daysInMonth;
  final DateTime focus;
  final List<ScheduledVisit> visits;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    if (dayIndex < 1 || dayIndex > daysInMonth) {
      return const SizedBox(height: 56);
    }
    final day = DateTime(focus.year, focus.month, dayIndex);
    final count = visits.where((v) => _sameDay(v.visitDate, day)).length;
    final isToday = _sameDay(day, DateTime.now());

    return InkWell(
      onTap: () => onSelectDay(day),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        height: 56,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isToday
              ? AppColors.ops.withValues(alpha: 0.08)
              : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            if (count > 0)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.ops.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ops,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({
    required this.visits,
    required this.onEdit,
    required this.onStatus,
    required this.onRemove,
  });

  final List<ScheduledVisit> visits;
  final ValueChanged<ScheduledVisit> onEdit;
  final void Function(ScheduledVisit, VisitStatus) onStatus;
  final ValueChanged<ScheduledVisit> onRemove;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      return Column(
        children: [
          for (final visit in visits) ...[
            _VisitCard(
              visit: visit,
              showDate: true,
              onEdit: () => onEdit(visit),
              onStatus: (s) => onStatus(visit, s),
              onRemove: () => onRemove(visit),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return SelloCard(
      padding: EdgeInsets.zero,
      child: SelloDataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Time')),
          DataColumn(label: Text('Customer')),
          DataColumn(label: Text('Rep')),
          DataColumn(label: Text('Priority')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final visit in visits)
            DataRow(
              cells: [
                DataCell(Text(SelloFormatters.date(visit.visitDate))),
                DataCell(Text(visit.preferredTimeLabel ?? '—')),
                DataCell(Text(visit.displayTitle)),
                DataCell(Text(visit.employeeName ?? '—')),
                DataCell(Text(visit.priority.label)),
                DataCell(_statusBadge(visit.status)),
                DataCell(
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit(visit);
                        case 'complete':
                          onStatus(visit, VisitStatus.completed);
                        case 'missed':
                          onStatus(visit, VisitStatus.missed);
                        case 'cancel':
                          onStatus(visit, VisitStatus.cancelled);
                        case 'remove':
                          onRemove(visit);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'complete',
                        child: Text('Mark completed'),
                      ),
                      PopupMenuItem(
                        value: 'missed',
                        child: Text('Mark missed'),
                      ),
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text('Cancel visit'),
                      ),
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.visit,
    required this.onEdit,
    required this.onStatus,
    required this.onRemove,
    this.showDate = false,
  });

  final ScheduledVisit visit;
  final VoidCallback onEdit;
  final ValueChanged<VisitStatus> onStatus;
  final VoidCallback onRemove;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  visit.displayTitle,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              _statusBadge(visit.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (showDate) SelloFormatters.date(visit.visitDate),
              visit.preferredTimeLabel ?? 'Anytime',
              visit.employeeName ?? 'Unassigned rep',
              if (visit.area != null) visit.area!,
              if (visit.purpose != null) visit.purpose!,
            ].join(' · '),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (visit.isOpen) ...[
                SelloButton(
                  label: 'Complete',
                  size: SelloButtonSize.small,
                  variant: SelloButtonVariant.outline,
                  onPressed: () => onStatus(VisitStatus.completed),
                ),
                SelloButton(
                  label: 'Missed',
                  size: SelloButtonSize.small,
                  variant: SelloButtonVariant.ghost,
                  onPressed: () => onStatus(VisitStatus.missed),
                ),
              ],
              SelloButton(
                label: 'Remove',
                size: SelloButtonSize.small,
                variant: SelloButtonVariant.ghost,
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _statusBadge(VisitStatus status) {
  final tone = switch (status) {
    VisitStatus.scheduled => SelloStatusTone.info,
    VisitStatus.completed => SelloStatusTone.success,
    VisitStatus.missed => SelloStatusTone.warning,
    VisitStatus.cancelled => SelloStatusTone.neutral,
    VisitStatus.unplanned => SelloStatusTone.brand,
  };
  return SelloStatusBadge(label: status.label, tone: tone);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
