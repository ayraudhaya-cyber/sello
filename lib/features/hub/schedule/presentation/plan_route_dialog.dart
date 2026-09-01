import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/schedule/schedule_planning_preferences.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/data/sri_lanka_areas.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/scheduled_visit.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Matches customer [CustomerSummary.city] to a free-text area / locality.
bool customerMatchesArea(CustomerSummary customer, String area) {
  final city = (customer.city ?? '').toLowerCase().trim();
  if (city.isEmpty) return false;
  final a = area.toLowerCase().trim();
  if (a.isEmpty) return false;
  if (city.contains(a) || a.contains(city)) return true;
  for (final part in a.split(RegExp(r'[–\-]'))) {
    final p = part.trim();
    if (p.isEmpty) continue;
    // Drop leading "Colombo 03" style numbers for suburb match.
    final suburb = p.replaceFirst(RegExp(r'^colombo\s*\d*\s*'), '').trim();
    if (suburb.isNotEmpty && (city.contains(suburb) || suburb.contains(city))) {
      return true;
    }
    if (city.contains(p) || p.contains(city)) return true;
  }
  return false;
}

/// Day planner — customers, an area, or both.
///
/// Returns one [VisitUpsertInput] per selected customer, or a single
/// area-only assignment when no customers are chosen.
class PlanRouteDialog extends ConsumerStatefulWidget {
  const PlanRouteDialog({
    super.key,
    required this.reps,
    required this.initialDate,
  });

  final List<SalesRepOption> reps;
  final DateTime initialDate;

  @override
  ConsumerState<PlanRouteDialog> createState() => _PlanRouteDialogState();
}

class _PlanRouteDialogState extends ConsumerState<PlanRouteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _prefsStore = SchedulePlanningPreferencesStore();
  final _selected = <String, CustomerSummary>{};

  String? _employeeId;
  late DateTime _visitDate;
  TimeOfDay? _preferredTime;
  String _area = '';
  String? _error;
  SchedulePlanningPreferences _prefs = SchedulePlanningPreferences.empty;
  bool _repFromRecent = false;
  bool _areaFromRecent = false;

  @override
  void initState() {
    super.initState();
    _visitDate = widget.initialDate;
    Future.microtask(_hydrateDefaults);
  }

  Future<void> _hydrateDefaults() async {
    final session = ref.read(currentSessionProvider);
    var employeeId = widget.reps.length == 1 ? widget.reps.first.id : null;
    var area = '';
    var repFromRecent = false;
    var areaFromRecent = false;
    var prefs = SchedulePlanningPreferences.empty;

    if (session != null) {
      prefs = await _prefsStore.load(session.company.id);
      if (!mounted) return;
      if (prefs.hasRecentRep &&
          widget.reps.any((r) => r.id == prefs.lastEmployeeId)) {
        employeeId = prefs.lastEmployeeId;
        repFromRecent = true;
      }
      if (prefs.hasRecentArea) {
        area = prefs.lastArea!;
        areaFromRecent = true;
      }
    } else if (widget.reps.length == 1) {
      employeeId = widget.reps.first.id;
    }

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _employeeId = employeeId;
      _area = area;
      _repFromRecent = repFromRecent;
      _areaFromRecent = areaFromRecent;
    });
  }

  Future<void> _pickCustomers() async {
    final picked = await showDialog<List<CustomerSummary>>(
      context: context,
      builder: (context) => _MultiCustomerPickerDialog(
        initiallySelected: _selected.values.toList(growable: false),
        areaFilter: _area.trim().isEmpty ? null : _area.trim(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addEntries(picked.map((c) => MapEntry(c.id, c)));
      _error = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _error = null;
    });
  }

  void _removeCustomer(String id) {
    setState(() => _selected.remove(id));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_employeeId == null || _employeeId!.isEmpty) {
      setState(() => _error = 'Choose a sales representative.');
      return;
    }
    if (_selected.isEmpty && _area.trim().isEmpty) {
      setState(
        () => _error = 'Add customers or choose an area to plan this visit.',
      );
      return;
    }

    final area = _area.trim().isEmpty ? null : _area.trim();
    final preferred = _preferredTime == null
        ? null
        : _preferredTime!.hour * 60 + _preferredTime!.minute;
    final stops = <VisitUpsertInput>[];
    if (_selected.isEmpty) {
      stops.add(
        VisitUpsertInput(
          employeeId: _employeeId!,
          visitDate: _visitDate,
          preferredTimeMinutes: preferred,
          area: area,
        ),
      );
    } else {
      var order = 0;
      for (final customer in _selected.values) {
        stops.add(
          VisitUpsertInput(
            customerId: customer.id,
            employeeId: _employeeId!,
            visitDate: _visitDate,
            preferredTimeMinutes: preferred,
            area: area,
            sortOrder: order++,
          ),
        );
      }
    }

    // Remember planning context only — never the selected stores/route stops.
    final session = ref.read(currentSessionProvider);
    if (session != null) {
      String? repName;
      for (final r in widget.reps) {
        if (r.id == _employeeId) {
          repName = r.name;
          break;
        }
      }
      await _prefsStore.rememberPlan(
        companyId: session.company.id,
        employeeId: _employeeId,
        employeeName: repName,
        area: area,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(stops);
  }

  List<String> get _areaSuggestions {
    final catalog = SriLankaAreas.suggestionsNear();
    final recent = _prefs.recentAreas;
    if (recent.isEmpty) return catalog;
    final seen = <String>{};
    final out = <String>[];
    for (final a in recent) {
      if (seen.add(a.toLowerCase())) out.add(a);
    }
    for (final a in catalog) {
      if (seen.add(a.toLowerCase())) out.add(a);
    }
    return out;
  }

  String get _whereSummary {
    final area = _area.trim();
    final n = _selected.length;
    if (area.isNotEmpty && n > 0) {
      return '$area · $n ${n == 1 ? 'customer' : 'customers'}';
    }
    if (area.isNotEmpty) return '$area · No specific customers';
    if (n == 1) return '1 customer selected';
    if (n > 1) return '$n customers selected';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final stopCount = _selected.length;
    final isNarrow = MediaQuery.sizeOf(context).width < 640;
    final recentRepName = _prefs.lastEmployeeName;
    final whereSummary = _whereSummary;
    final hasArea = _area.trim().isNotEmpty;

    return SelloFormDialog(
      title: 'Plan visits',
      subtitle: 'Who, when, and where they should work.',
      formKey: _formKey,
      maxWidth: 720,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                color: AppColors.error,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const _PlanSectionLabel('Who'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _employeeId != null &&
                    widget.reps.any((r) => r.id == _employeeId)
                ? _employeeId
                : null,
            decoration: InputDecoration(
              label: SelloFieldLabel.decorationLabel(
                'Sales representative',
                required: true,
              ),
              helperText: _repFromRecent && recentRepName != null
                  ? 'Recently used — $recentRepName'
                  : widget.reps.isEmpty
                      ? 'No field-visit eligible team members yet'
                      : null,
            ),
            items: [
              for (final rep in widget.reps)
                DropdownMenuItem(value: rep.id, child: Text(rep.name)),
            ],
            onChanged: (value) => setState(() {
              _employeeId = value;
              _repFromRecent = false;
            }),
            validator: (value) =>
                value == null || value.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 20),
          const _PlanSectionLabel('When'),
          const SizedBox(height: 8),
          if (isNarrow) ...[
            _DateField(
              date: _visitDate,
              onPick: (d) => setState(() => _visitDate = d),
            ),
            const SizedBox(height: 14),
            _TimeField(
              time: _preferredTime,
              onPick: (t) => setState(() => _preferredTime = t),
              onClear: () => setState(() => _preferredTime = null),
            ),
          ] else
            SelloFormRow(
              left: _DateField(
                date: _visitDate,
                onPick: (d) => setState(() => _visitDate = d),
              ),
              right: _TimeField(
                time: _preferredTime,
                onPick: (t) => setState(() => _preferredTime = t),
                onClear: () => setState(() => _preferredTime = null),
              ),
            ),
          const SizedBox(height: 20),
          const _PlanSectionLabel('Where'),
          if (whereSummary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              whereSummary,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SelloAutocompleteField(
            value: _area,
            suggestions: _areaSuggestions,
            onChanged: (value) => setState(() {
              _area = value;
              _areaFromRecent = false;
              _error = null;
            }),
            label: 'Area',
            hint: _areaFromRecent && _prefs.hasRecentArea
                ? 'Recently used — ${_prefs.lastArea}'
                : 'e.g. Mount Lavinia, Colombo…',
            maxSuggestions: 16,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  stopCount == 0
                      ? (hasArea
                          ? 'No specific customers'
                          : 'Customers optional')
                      : '$stopCount ${stopCount == 1 ? 'customer' : 'customers'}',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: stopCount == 0
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (stopCount > 0)
                TextButton(
                  onPressed: _clearSelection,
                  child: const Text('Clear'),
                ),
              SelloButton(
                label: stopCount == 0 ? 'Select customers' : 'Edit customers',
                variant: SelloButtonVariant.outline,
                size: SelloButtonSize.small,
                onPressed: _pickCustomers,
              ),
            ],
          ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _selected.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final customer = _selected.values.elementAt(index);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      customer.name,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (customer.city != null) customer.city!,
                        if (customer.phone != null) customer.phone!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _removeCustomer(customer.id),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.ghost,
        primaryLabel: stopCount == 0
            ? (hasArea ? 'Plan area' : 'Plan visits')
            : 'Plan $stopCount ${stopCount == 1 ? 'stop' : 'stops'}',
        onPrimary: _submit,
      ),
    );
  }
}

class _PlanSectionLabel extends StatelessWidget {
  const _PlanSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.textTertiary,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onPick});

  final DateTime date;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date'),
        child: Text(SelloFormatters.date(date)),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.time,
    required this.onPick,
    required this.onClear,
  });

  final TimeOfDay? time;
  final ValueChanged<TimeOfDay> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time ?? TimeOfDay.now(),
        );
        if (picked != null) onPick(picked);
      },
      onLongPress: time == null ? null : onClear,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Preferred time',
          suffixIcon: time == null
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                ),
        ),
        child: Text(time == null ? 'Anytime' : time!.format(context)),
      ),
    );
  }
}

/// Lightweight single-stop edit (existing scheduled visit).
class EditVisitDialog extends ConsumerStatefulWidget {
  const EditVisitDialog({
    super.key,
    required this.visit,
    required this.reps,
  });

  final ScheduledVisit visit;
  final List<SalesRepOption> reps;

  @override
  ConsumerState<EditVisitDialog> createState() => _EditVisitDialogState();
}

class _EditVisitDialogState extends ConsumerState<EditVisitDialog> {
  final _formKey = GlobalKey<FormState>();
  CustomerSummary? _customer;
  String? _employeeId;
  late DateTime _visitDate;
  TimeOfDay? _preferredTime;
  String _area = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final visit = widget.visit;
    _visitDate = visit.visitDate;
    _employeeId = visit.employeeId;
    _area = visit.area ?? '';
    if (visit.preferredTime != null) {
      final m = visit.preferredTime!;
      _preferredTime = TimeOfDay(hour: m ~/ 60, minute: m % 60);
    }
    Future.microtask(() async {
      final customerId = visit.customerId;
      if (customerId == null || customerId.isEmpty) return;
      try {
        final customer = await ref
            .read(customerRepositoryProvider)
            .fetchById(customerId);
        if (!mounted) return;
        setState(() => _customer = customer);
      } catch (_) {}
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_employeeId == null || _employeeId!.isEmpty) {
      setState(() => _error = 'Choose a sales representative.');
      return;
    }
    if (!widget.visit.isCustomerStop && _area.trim().isEmpty) {
      setState(
        () => _error = 'Add customers or choose an area to plan this visit.',
      );
      return;
    }
    Navigator.of(context).pop(
      VisitUpsertInput(
        id: widget.visit.id,
        customerId: widget.visit.customerId,
        employeeId: _employeeId!,
        visitDate: _visitDate,
        preferredTimeMinutes: _preferredTime == null
            ? null
            : _preferredTime!.hour * 60 + _preferredTime!.minute,
        area: _area.trim().isEmpty ? null : _area.trim(),
        priority: widget.visit.priority,
        purpose: widget.visit.purpose,
        notes: widget.visit.notes,
        expectedDurationMinutes: widget.visit.expectedDurationMinutes,
        status: widget.visit.status,
        sortOrder: widget.visit.sortOrder,
        branchId: widget.visit.branchId,
        recurrenceRule: widget.visit.recurrenceRule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: widget.visit.isAreaAssignment ? 'Edit area' : 'Edit stop',
      subtitle: _customer?.name ?? widget.visit.displayTitle,
      formKey: _formKey,
      maxWidth: 560,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            value: _employeeId != null &&
                    widget.reps.any((r) => r.id == _employeeId)
                ? _employeeId
                : null,
            decoration: const InputDecoration(
              label: SelloFieldLabel(
                label: 'Sales representative',
                required: true,
                style: TextStyle(fontFamily: AppTypography.fontFamily),
              ),
            ),
            items: [
              for (final rep in widget.reps)
                DropdownMenuItem(value: rep.id, child: Text(rep.name)),
            ],
            onChanged: (value) => setState(() => _employeeId = value),
            validator: (value) =>
                value == null || value.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          SelloFormRow(
            left: _DateField(
              date: _visitDate,
              onPick: (d) => setState(() => _visitDate = d),
            ),
            right: _TimeField(
              time: _preferredTime,
              onPick: (t) => setState(() => _preferredTime = t),
              onClear: () => setState(() => _preferredTime = null),
            ),
          ),
          const SizedBox(height: 14),
          SelloAutocompleteField(
            value: _area,
            suggestions: SriLankaAreas.suggestionsNear(),
            onChanged: (value) => setState(() => _area = value),
            label: 'Area',
            hint: 'Coverage area for this stop',
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.ghost,
        primaryLabel: 'Save changes',
        onPrimary: _submit,
      ),
    );
  }
}

class _MultiCustomerPickerDialog extends ConsumerStatefulWidget {
  const _MultiCustomerPickerDialog({
    required this.initiallySelected,
    this.areaFilter,
  });

  final List<CustomerSummary> initiallySelected;
  final String? areaFilter;

  @override
  ConsumerState<_MultiCustomerPickerDialog> createState() =>
      _MultiCustomerPickerDialogState();
}

class _MultiCustomerPickerDialogState
    extends ConsumerState<_MultiCustomerPickerDialog> {
  final _search = TextEditingController();
  final _selected = <String, CustomerSummary>{};
  Timer? _debounce;
  List<CustomerSummary> _items = const [];
  bool _loading = true;
  bool _areaOnly = false;

  @override
  void initState() {
    super.initState();
    for (final c in widget.initiallySelected) {
      _selected[c.id] = c;
    }
    _areaOnly = widget.areaFilter != null && widget.areaFilter!.trim().isNotEmpty;
    Future.microtask(() => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([String search = '']) async {
    setState(() => _loading = true);
    try {
      final result = await ref.read(customerRepositoryProvider).fetchCustomers(
            search: search,
            isActive: true,
            pageSize: 80,
          );
      var items = result.items;
      final area = widget.areaFilter?.trim();
      if (_areaOnly && area != null && area.isNotEmpty) {
        items = items
            .where((c) => customerMatchesArea(c, area))
            .toList(growable: false);
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  void _toggle(CustomerSummary customer) {
    setState(() {
      if (_selected.containsKey(customer.id)) {
        _selected.remove(customer.id);
      } else {
        _selected[customer.id] = customer;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.areaFilter?.trim();
    return SelloFormDialog(
      title: 'Select customers',
      subtitle: _selected.isEmpty
          ? 'Tap to select stops'
          : '${_selected.length} selected',
      maxWidth: 560,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloSearchBar(
            controller: _search,
            hint: 'Search customers…',
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 250),
                () => _load(value),
              );
            },
          ),
          if (area != null && area.isNotEmpty) ...[
            const SizedBox(height: 8),
            FilterChip(
              label: Text(_areaOnly ? 'In $area' : 'All areas'),
              selected: _areaOnly,
              onSelected: (value) {
                setState(() => _areaOnly = value);
                _load(_search.text);
              },
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _items.isEmpty
                    ? const Center(child: Text('No customers found'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final customer = _items[index];
                          final checked = _selected.containsKey(customer.id);
                          return CheckboxListTile(
                            value: checked,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(customer.name),
                            subtitle: Text(
                              [
                                if (customer.phone != null) customer.phone!,
                                if (customer.city != null) customer.city!,
                              ].join(' · '),
                            ),
                            onChanged: (_) => _toggle(customer),
                          );
                        },
                      ),
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.ghost,
        primaryLabel: _selected.isEmpty
            ? 'Done'
            : 'Add ${_selected.length} ${_selected.length == 1 ? 'customer' : 'customers'}',
        onPrimary: () => Navigator.pop(
          context,
          _selected.values.toList(growable: false),
        ),
      ),
    );
  }
}
