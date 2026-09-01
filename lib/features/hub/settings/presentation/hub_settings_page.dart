import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/hub/settings/presentation/about_settings_section.dart';
import 'package:sello/features/hub/settings/presentation/branding_settings_section.dart';
import 'package:sello/features/hub/settings/presentation/outbound_messaging_settings.dart';
import 'package:sello/features/hub/settings/presentation/reliability_settings_section.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/features/hub/settings/settings_sections.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/financial_visibility.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/utils/product_industry_recommendations.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubSettingsPage extends ConsumerStatefulWidget {
  const HubSettingsPage({super.key});

  @override
  ConsumerState<HubSettingsPage> createState() => _HubSettingsPageState();
}

class _HubSettingsPageState extends ConsumerState<HubSettingsPage> {
  SettingsSectionId _section = SettingsSectionId.business;
  late final TextEditingController _reorderLevel;
  String? _reorderError;

  static const _currencies = <String>[
    'USD',
    'EUR',
    'GBP',
    'LKR',
    'INR',
    'AED',
    'AUD',
    'CAD',
    'SGD',
    'JPY',
  ];

  static const _monthLabels = <String>[
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

  @override
  void initState() {
    super.initState();
    _reorderLevel = TextEditingController(
      text: CompanySettings.defaults.defaultReorderLevel.toString(),
    );
  }

  @override
  void dispose() {
    _reorderLevel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final draft = ref.read(hubSettingsProvider).draft;
    if (draft == null) return;

    final reorderText = _reorderLevel.text.trim();
    final reorder = int.tryParse(reorderText);
    if (reorder == null || reorder < 0 || reorderText != reorder.toString()) {
      setState(() => _reorderError = 'Enter a whole number of 0 or greater.');
      if (_section != SettingsSectionId.inventory) {
        setState(() => _section = SettingsSectionId.inventory);
      }
      return;
    }
    setState(() => _reorderError = null);

    ref
        .read(hubSettingsProvider.notifier)
        .patchDraft(
          (current) => current.copyWith(defaultReorderLevel: reorder),
        );

    final error = await ref.read(hubSettingsProvider.notifier).save();
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    SelloSnackbars.success(context, 'Settings saved');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubSettingsProvider);
    final showBranding = ref.watch(canAccessBrandingSettingsProvider);
    final section = showBranding || _section != SettingsSectionId.branding
        ? _section
        : SettingsSectionId.business;

    ref.listen(hubSettingsProvider, (previous, next) {
      if (previous?.settings == null && next.settings != null) {
        _reorderLevel.text = next.settings!.defaultReorderLevel.toString();
      }
    });

    return AppPageScaffold(
      title: 'Settings',
      subtitle: 'Preferences that shape how Sello works for your business.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      scrollable: false,
      padding: EdgeInsets.fromLTRB(
        context.pagePadding,
        context.isMobile ? AppSpacing.lg : AppSpacing.xl,
        context.pagePadding,
        0,
      ),
      body: state.isLoading && state.settings == null
          ? const SelloFadeIn(child: SelloSettingsSkeleton())
          : state.errorMessage != null && state.settings == null
          ? SizedBox(
              height: 320,
              child: SelloStateView.error(
                title: 'Unable to load settings',
                message: state.errorMessage,
                actionLabel: 'Try again',
                onAction: () => ref.read(hubSettingsProvider.notifier).load(),
              ),
            )
          : SelloFadeIn(
              child: ResponsiveBuilder(
                mobile: (_) => _buildStacked(
                  state,
                  section: section,
                  showBranding: showBranding,
                ),
                tablet: (_) => _buildSplit(
                  state,
                  navWidth: 220,
                  section: section,
                  showBranding: showBranding,
                ),
                desktop: (_) => _buildSplit(
                  state,
                  navWidth: 240,
                  section: section,
                  showBranding: showBranding,
                ),
              ),
            ),
    );
  }

  Widget _buildSplit(
    HubSettingsState state, {
    required double navWidth,
    required SettingsSectionId section,
    required bool showBranding,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: navWidth,
          child: SingleChildScrollView(
            child: _buildNav(section: section, showBranding: showBranding),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: _buildContent(state, section)),
      ],
    );
  }

  Widget _buildStacked(
    HubSettingsState state, {
    required SettingsSectionId section,
    required bool showBranding,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final navMax = (constraints.maxHeight * 0.4).clamp(160.0, 280.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: navMax),
              child: SingleChildScrollView(
                child: _buildNav(section: section, showBranding: showBranding),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildContent(state, section)),
          ],
        );
      },
    );
  }

  Widget _buildNav({
    required SettingsSectionId section,
    required bool showBranding,
  }) {
    return SettingsSideNav(
      sections: [
        for (final item in kSettingsSections)
          if (item.id != SettingsSectionId.branding || showBranding)
            (
              id: item.id.name,
              label: item.label,
              icon: item.icon,
              comingSoon: item.comingSoon,
            ),
      ],
      selected: section.name,
      onSelect: (id) {
        final match = SettingsSectionId.values.byName(id);
        setState(() => _section = match);
      },
    );
  }

  Widget _buildContent(HubSettingsState state, SettingsSectionId section) {
    return SizedBox.expand(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [...previousChildren, ?currentChild],
          );
        },
        child: KeyedSubtree(
          key: ValueKey(section),
          child: switch (section) {
            SettingsSectionId.business => _BusinessSection(
              state: state,
              currencies: _currencies,
              monthLabels: _monthLabels,
              onChanged: (update) =>
                  ref.read(hubSettingsProvider.notifier).patchDraft(update),
              onSave: _save,
              onDiscard: () {
                ref.read(hubSettingsProvider.notifier).discardDraft();
                final level = ref
                    .read(hubSettingsProvider)
                    .settings
                    ?.defaultReorderLevel;
                if (level != null) _reorderLevel.text = level.toString();
                setState(() => _reorderError = null);
              },
            ),
            SettingsSectionId.branding => const BrandingSettingsSection(),
            SettingsSectionId.inventory => _InventorySection(
              state: state,
              reorderController: _reorderLevel,
              reorderError: _reorderError,
              onReorderChanged: (value) {
                setState(() => _reorderError = null);
                final parsed = int.tryParse(value.trim());
                if (parsed != null && parsed >= 0) {
                  ref
                      .read(hubSettingsProvider.notifier)
                      .patchDraft(
                        (c) => c.copyWith(defaultReorderLevel: parsed),
                      );
                }
              },
              onChanged: (update) =>
                  ref.read(hubSettingsProvider.notifier).patchDraft(update),
              onSave: _save,
              onDiscard: () {
                ref.read(hubSettingsProvider.notifier).discardDraft();
                final level = ref
                    .read(hubSettingsProvider)
                    .settings
                    ?.defaultReorderLevel;
                if (level != null) _reorderLevel.text = level.toString();
                setState(() => _reorderError = null);
              },
            ),
            SettingsSectionId.productFields => const _ProductFieldsSection(),
            SettingsSectionId.ordersInvoices => _OrdersInvoicesSection(
              state: state,
              onChanged: (update) =>
                  ref.read(hubSettingsProvider.notifier).patchDraft(update),
              onSave: _save,
              onDiscard: () =>
                  ref.read(hubSettingsProvider.notifier).discardDraft(),
            ),
            SettingsSectionId.notifications => const _NotificationsSection(),
            SettingsSectionId.reliability => SettingsSectionScaffold(
              body: const ReliabilitySettingsSection(),
            ),
            SettingsSectionId.about => SettingsSectionScaffold(
              body: const AboutSettingsSection(),
            ),
            SettingsSectionId.appearance ||
            SettingsSectionId.company ||
            SettingsSectionId.permissions => _ComingSoonPanel(section: section),
          },
        ),
      ),
    );
  }
}

class _BusinessSection extends StatelessWidget {
  const _BusinessSection({
    required this.state,
    required this.currencies,
    required this.monthLabels,
    required this.onChanged,
    required this.onSave,
    required this.onDiscard,
  });

  final HubSettingsState state;
  final List<String> currencies;
  final List<String> monthLabels;
  final void Function(CompanySettings Function(CompanySettings)) onChanged;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final draft = state.effective;
    final currencyItems = {
      ...currencies,
      if (!currencies.contains(draft.currency)) draft.currency,
    }.toList()..sort();

    return SettingsSectionScaffold(
      actionBar: SettingsActionBar(
        enabled: state.isDirty,
        saving: state.isSaving,
        onSave: onSave,
        onDiscard: onDiscard,
      ),
      body: SettingsGroupCard(
        title: 'Business',
        description: 'Financial and regional defaults used across Sello.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSubgroup(
              title: 'Financial & regional',
              child: SettingsTwoUp(
                children: [
                  SettingsCompactField(
                    label: 'Default currency',
                    helper: 'Defaults to your company currency.',
                    child: SelloDropdown<String>(
                      value: draft.currency,
                      items: [
                        for (final code in currencyItems)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        onChanged((c) => c.copyWith(currency: value));
                      },
                    ),
                  ),
                  SettingsCompactField(
                    label: 'Currency symbol position',
                    helper: 'Controls where the currency symbol appears.',
                    child: SelloDropdown<CurrencyPosition>(
                      value: draft.currencyPosition,
                      items: const [
                        DropdownMenuItem(
                          value: CurrencyPosition.before,
                          child: Text('Before amount'),
                        ),
                        DropdownMenuItem(
                          value: CurrencyPosition.after,
                          child: Text('After amount'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        onChanged((c) => c.copyWith(currencyPosition: value));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Divider(height: 1, color: AppColors.outlinePanel),
            const SizedBox(height: 22),
            SettingsSubgroup(
              title: 'Accounting',
              child: SettingsTwoUp(
                children: [
                  SettingsCompactField(
                    label: 'Financial year',
                    helper: 'The month your reporting year starts.',
                    child: SelloDropdown<int>(
                      value: draft.financialYearStartMonth,
                      items: [
                        for (var i = 0; i < monthLabels.length; i++)
                          DropdownMenuItem(
                            value: i + 1,
                            child: Text(monthLabels[i]),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        onChanged(
                          (c) => c.copyWith(financialYearStartMonth: value),
                        );
                      },
                    ),
                  ),
                  SettingsCompactField(
                    label: 'Default tax mode',
                    helper:
                        'Used as the default when pricing; editable per sale.',
                    child: SelloDropdown<TaxMode>(
                      value: draft.defaultTaxMode,
                      items: [
                        for (final mode in TaxMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        onChanged((c) => c.copyWith(defaultTaxMode: value));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventorySection extends StatelessWidget {
  const _InventorySection({
    required this.state,
    required this.reorderController,
    required this.reorderError,
    required this.onReorderChanged,
    required this.onChanged,
    required this.onSave,
    required this.onDiscard,
  });

  final HubSettingsState state;
  final TextEditingController reorderController;
  final String? reorderError;
  final ValueChanged<String> onReorderChanged;
  final void Function(CompanySettings Function(CompanySettings)) onChanged;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final draft = state.effective;

    return SettingsSectionScaffold(
      actionBar: SettingsActionBar(
        enabled: state.isDirty,
        saving: state.isSaving,
        onSave: onSave,
        onDiscard: onDiscard,
      ),
      body: SettingsGroupCard(
        title: 'Inventory',
        description:
            'Defaults for new products. You can still override them per item.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSubgroup(
              title: 'Stock defaults',
              child: SettingsTwoUp(
                children: [
                  SettingsCompactField(
                    label: 'Default reorder level',
                    helper: 'Used when creating a product.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelloTextField(
                          controller: reorderController,
                          hint: 'e.g. 5',
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            NonNegativeIntegerFormatter(),
                          ],
                          onChanged: onReorderChanged,
                        ),
                        if (reorderError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            reorderError!,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 12.5,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SettingsCompactField(
                    label: 'Default product status',
                    helper: 'Status assigned to newly created products.',
                    child: SelloDropdown<DefaultProductStatus>(
                      value: draft.defaultProductStatus,
                      items: [
                        for (final status in DefaultProductStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        onChanged(
                          (c) => c.copyWith(defaultProductStatus: value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Divider(height: 1, color: AppColors.outlinePanel),
            const SizedBox(height: 22),
            SettingsSubgroup(
              title: 'Stock rules',
              child: SettingsTwoUp(
                children: [
                  SelloStatusToggle(
                    value: draft.enableLowStockAlert,
                    label: 'Low stock alert enabled',
                    helper:
                        'Show alerts when stock falls to or below the reorder level.',
                    onChanged: (value) => onChanged(
                      (c) => c.copyWith(enableLowStockAlert: value),
                    ),
                  ),
                  SelloStatusToggle(
                    value: draft.allowNegativeStock,
                    label: 'Allow negative stock',
                    helper:
                        'When off, sales and adjustments cannot push stock below zero.',
                    onChanged: (value) =>
                        onChanged((c) => c.copyWith(allowNegativeStock: value)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hubSettingsProvider);
    return SettingsSectionScaffold(
      actionBar: SettingsActionBar(
        enabled: state.isDirty,
        saving: state.isSaving,
        onSave: () async {
          final error = await ref.read(hubSettingsProvider.notifier).save();
          if (!context.mounted) return;
          if (error != null) {
            SelloSnackbars.error(context, error);
          } else {
            SelloSnackbars.success(context, 'Messaging settings saved.');
          }
        },
        onDiscard: () => ref.read(hubSettingsProvider.notifier).discardDraft(),
      ),
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NotificationsPrefsSection(),
          SizedBox(height: AppSpacing.lg),
          OutboundMessagingSettingsCard(),
        ],
      ),
    );
  }
}

class _NotificationsPrefsSection extends ConsumerStatefulWidget {
  const _NotificationsPrefsSection();

  @override
  ConsumerState<_NotificationsPrefsSection> createState() =>
      _NotificationsPrefsSectionState();
}

class _NotificationsPrefsSectionState
    extends ConsumerState<_NotificationsPrefsSection> {
  List<NotificationPreference>? _prefs;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to manage notification preferences.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await ref
          .read(notificationRepositoryProvider)
          .fetchPreferences(employeeId: session.employee.id);
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load preferences. Apply migration 027 if missing.';
      });
    }
  }

  Future<void> _toggleInApp(NotificationPreference pref, bool value) async {
    final updated = pref.copyWith(channelInApp: value);
    setState(() {
      _prefs = [
        for (final p in _prefs ?? const <NotificationPreference>[])
          if (p.id == pref.id) updated else p,
      ];
      _saving = true;
    });
    try {
      await ref.read(notificationRepositoryProvider).updatePreference(updated);
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to save preference.');
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsGroupCard(
      title: 'Your inbox',
      description:
          'Choose which business events appear in your personal in-app inbox.',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _error != null
          ? SelloStateView.error(
              title: 'Unable to load preferences',
              message: _error!,
              actionLabel: 'Try again',
              onAction: _load,
            )
          : (_prefs == null || _prefs!.isEmpty)
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Preferences will appear after migrations 027–028 are applied.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTwoColumn(
                  gap: 14,
                  children: [
                    for (final pref in _prefs!)
                      SettingsPreferenceRow(
                        label: pref.category.label,
                        helper: [
                          if (pref.channelInApp) 'In-app',
                          if (pref.channelPush) 'Push',
                          if (pref.channelEmail) 'Email',
                          if (pref.channelSms) 'SMS',
                          if (pref.channelWhatsapp) 'WhatsApp',
                          if (!pref.channelInApp &&
                              !pref.channelPush &&
                              !pref.channelEmail &&
                              !pref.channelSms &&
                              !pref.channelWhatsapp)
                            'Muted',
                        ].join(' · '),
                        value: pref.channelInApp,
                        enabled: !_saving,
                        onChanged: (value) => _toggleInApp(pref, value),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const Divider(height: 1, color: AppColors.outlinePanel),
                const SizedBox(height: 16),
                const _ReservedChannelsPanel(),
              ],
            ),
    );
  }
}

class _ReservedChannelsPanel extends StatelessWidget {
  const _ReservedChannelsPanel();

  static const _channels = ['Push', 'Email', 'SMS', 'WhatsApp'];

  @override
  Widget build(BuildContext context) {
    return SettingsExpandable(
      title: 'Future channels',
      subtitle: 'Reserved — not delivered yet.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Delivery channels ready in the model: In-app (live), '
            'Push, Email, SMS, WhatsApp. Daily / weekly summaries, '
            'AI digests, and webhooks will subscribe to the same '
            'business event bus.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SettingsTwoColumn(
            gap: 10,
            children: [
              for (final label in _channels)
                SettingsPreferenceRow(
                  label: label,
                  value: false,
                  enabled: false,
                  onChanged: null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductFieldsSection extends ConsumerStatefulWidget {
  const _ProductFieldsSection();

  @override
  ConsumerState<_ProductFieldsSection> createState() =>
      _ProductFieldsSectionState();
}

class _ProductFieldsSectionState extends ConsumerState<_ProductFieldsSection> {
  List<CompanyProductField>? _draft;
  bool _saving = false;
  String _search = '';
  bool _browsingIndustry = false;
  ProductIndustry? _selectedIndustry;

  List<CompanyProductField> _effective(ProductFieldConfig config) =>
      _draft ?? List.of(config.fields);

  bool _isDirty(ProductFieldConfig config) {
    if (_draft == null) return false;
    if (_draft!.length != config.fields.length) return true;
    for (var i = 0; i < _draft!.length; i++) {
      if (_draft![i] != config.fields[i]) return true;
    }
    return false;
  }

  bool _isSettingsField(CompanyProductField field) =>
      field.definition.settingsVisible && field.fieldKey != 'description';

  bool _matchesSearch(CompanyProductField field) {
    final needle = _search.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final hay = [
      field.label,
      field.fieldKey,
      field.definition.helpText,
      field.definition.group.label,
      field.definition.fieldType.label,
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(needle);
  }

  List<CompanyProductField> _sorted(Iterable<CompanyProductField> fields) {
    final list = fields.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  void _patch(
    String fieldKey,
    CompanyProductField Function(CompanyProductField) update,
  ) {
    final config = ref.read(productFieldConfigProvider).valueOrNull;
    if (config == null) return;
    final current = _effective(config);
    setState(() {
      _draft = [
        for (final field in current)
          if (field.fieldKey == fieldKey) update(field) else field,
      ];
    });
  }

  void _applyIndustryRecommendations(ProductIndustry industry) {
    final config = ref.read(productFieldConfigProvider).valueOrNull;
    if (config == null) return;
    final current = _effective(config);
    setState(() {
      _draft = ProductIndustryRecommendations.apply(
        fields: current,
        industry: industry,
      );
    });
    SelloSnackbars.success(
      context,
      '${industry.label} recommendations enabled — review under Enabled.',
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    final error = await ref
        .read(productFieldConfigProvider.notifier)
        .save(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    setState(() => _draft = null);
    SelloSnackbars.success(context, 'Product details saved');
  }

  void _discard() => setState(() {
    _draft = null;
  });

  void _onFieldChanged(CompanyProductField updated) =>
      _patch(updated.fieldKey, (_) => updated);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productFieldConfigProvider);
    final config = async.valueOrNull;

    return SettingsSectionScaffold(
      actionBar: config == null
          ? null
          : SettingsActionBar(
              enabled: _isDirty(config) || _saving,
              saving: _saving,
              onSave: _save,
              onDiscard: _discard,
            ),
      body: async.when(
        loading: () => SettingsGroupCard(
          title: 'Product Details',
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
        error: (error, _) => SettingsGroupCard(
          title: 'Product Details',
          child: SelloStateView.error(
            title: 'Unable to load product details',
            message: error.toString(),
            actionLabel: 'Try again',
            onAction: () =>
                ref.read(productFieldConfigProvider.notifier).reload(),
          ),
        ),
        data: (config) {
          final fields = _effective(
            config,
          ).where(_isSettingsField).toList(growable: false);
          final searching = _search.trim().isNotEmpty;

          final enabled = _sorted(
            fields.where((f) => f.enabled && _matchesSearch(f)),
          );
          final commonAvailable = _sorted(
            fields.where(
              (f) =>
                  !f.enabled &&
                  f.definition.group == ProductDetailGroup.common &&
                  _matchesSearch(f),
            ),
          );

          // Industry: only when browsing a selection, or when searching.
          final industryPool = fields.where((f) {
            if (f.enabled) return false;
            if (f.definition.group == ProductDetailGroup.common) return false;
            if (!_matchesSearch(f)) return false;
            if (searching) return true;
            if (!_browsingIndustry || _selectedIndustry == null) return false;
            return f.definition.group == _selectedIndustry!.detailGroup;
          });
          final industryFields = _sorted(industryPool);

          // When searching, group industry hits by industry for clarity.
          final industryByGroup =
              <ProductDetailGroup, List<CompanyProductField>>{};
          if (searching) {
            for (final field in industryFields) {
              industryByGroup
                  .putIfAbsent(field.definition.group, () => [])
                  .add(field);
            }
          }

          final hasAny =
              enabled.isNotEmpty ||
              commonAvailable.isNotEmpty ||
              industryFields.isNotEmpty ||
              (_browsingIndustry && !searching);

          return SettingsGroupCard(
            title: 'Product Details',
            description:
                'Enable the details you need. Description stays on the product form.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelloSearchBar(
                  hint: 'Search product details…',
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 20),
                if (!hasAny)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      'No product details match your search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                else ...[
                  if (enabled.isNotEmpty) ...[
                    const _SectionHeader(
                      title: 'Enabled',
                      subtitle: 'Details active on your products',
                    ),
                    const SizedBox(height: 12),
                    _ProductDetailsGrid(
                      fields: enabled,
                      onChanged: _onFieldChanged,
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (commonAvailable.isNotEmpty || !searching) ...[
                    const _SectionHeader(
                      title: 'Common',
                      subtitle: 'Useful across most businesses',
                    ),
                    const SizedBox(height: 12),
                    if (commonAvailable.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'All common details are enabled above.',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      _ProductDetailsGrid(
                        fields: commonAvailable,
                        onChanged: _onFieldChanged,
                      ),
                    const SizedBox(height: 22),
                  ],
                  if (searching && industryByGroup.isNotEmpty) ...[
                    for (final group in ProductDetailGroup.settingsOrder)
                      if ((industryByGroup[group] ?? const []).isNotEmpty) ...[
                        _SectionHeader(
                          title: group.label,
                          subtitle: 'Industry detail',
                        ),
                        const SizedBox(height: 12),
                        _ProductDetailsGrid(
                          fields: industryByGroup[group]!,
                          onChanged: _onFieldChanged,
                        ),
                        const SizedBox(height: 22),
                      ],
                  ] else
                    _IndustryBrowsePanel(
                      browsing: _browsingIndustry,
                      selected: _selectedIndustry,
                      fields: industryFields,
                      onToggleBrowse: () => setState(() {
                        _browsingIndustry = !_browsingIndustry;
                        if (!_browsingIndustry) _selectedIndustry = null;
                      }),
                      onSelectIndustry: (industry) => setState(() {
                        _selectedIndustry = _selectedIndustry == industry
                            ? null
                            : industry;
                      }),
                      onApplyRecommendations: _selectedIndustry == null
                          ? null
                          : () => _applyIndustryRecommendations(
                              _selectedIndustry!,
                            ),
                      onChanged: _onFieldChanged,
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: AppColors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textFaint,
            ),
          ),
        ],
      ],
    );
  }
}

class _IndustryBrowsePanel extends StatelessWidget {
  const _IndustryBrowsePanel({
    required this.browsing,
    required this.selected,
    required this.fields,
    required this.onToggleBrowse,
    required this.onSelectIndustry,
    required this.onChanged,
    this.onApplyRecommendations,
  });

  final bool browsing;
  final ProductIndustry? selected;
  final List<CompanyProductField> fields;
  final VoidCallback onToggleBrowse;
  final ValueChanged<ProductIndustry> onSelectIndustry;
  final ValueChanged<CompanyProductField> onChanged;
  final VoidCallback? onApplyRecommendations;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggleBrowse,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: browsing
                  ? context.brandAccent.withValues(alpha: 0.06)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: browsing
                    ? context.brandAccent.withValues(alpha: 0.28)
                    : AppColors.outlinePanel,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        browsing
                            ? 'Browsing industry details'
                            : 'Browse Industry Details',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: browsing
                              ? context.brandAccent
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        browsing
                            ? 'Choose one industry — only its details are shown'
                            : 'For Hardware, Stationery, and more',
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  browsing ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppDurations.normal,
          curve: AppCurves.standard,
          alignment: Alignment.topCenter,
          child: browsing
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final industry in ProductIndustry.values)
                            ChoiceChip(
                              label: Text(
                                '${industry.emoji}  ${industry.label}',
                              ),
                              selected: selected == industry,
                              onSelected: (_) => onSelectIndustry(industry),
                              selectedColor: context.brandAccent.withValues(
                                alpha: 0.14,
                              ),
                              labelStyle: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: selected == industry
                                    ? context.brandAccent
                                    : AppColors.textSecondary,
                              ),
                              side: BorderSide(
                                color: selected == industry
                                    ? context.brandAccent.withValues(
                                        alpha: 0.35,
                                      )
                                    : AppColors.outlinePanel,
                              ),
                              backgroundColor: AppColors.surface,
                            ),
                        ],
                      ),
                      if (selected != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                '${selected!.emoji}  ${selected!.label}',
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (onApplyRecommendations != null)
                              TextButton(
                                onPressed: onApplyRecommendations,
                                child: const Text('Enable recommended'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (fields.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'All details for this industry are already enabled.',
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        else
                          _ProductDetailsGrid(
                            fields: fields,
                            onChanged: onChanged,
                          ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: Text(
                            'Select an industry to see its product details.',
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ProductDetailsGrid extends StatelessWidget {
  const _ProductDetailsGrid({required this.fields, required this.onChanged});

  final List<CompanyProductField> fields;
  final ValueChanged<CompanyProductField> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = context.responsiveValue(
          mobile: 1,
          tablet: 2,
          desktop: 2,
        );
        const gap = 12.0;

        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                _ProductDetailSettingsCard(
                  key: ValueKey(fields[i].fieldKey),
                  field: fields[i],
                  onChanged: onChanged,
                ),
              ],
            ],
          );
        }

        final left = <CompanyProductField>[];
        final right = <CompanyProductField>[];
        for (var i = 0; i < fields.length; i++) {
          (i.isEven ? left : right).add(fields[i]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < left.length; i++) ...[
                    if (i > 0) const SizedBox(height: gap),
                    _ProductDetailSettingsCard(
                      key: ValueKey(left[i].fieldKey),
                      field: left[i],
                      onChanged: onChanged,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < right.length; i++) ...[
                    if (i > 0) const SizedBox(height: gap),
                    _ProductDetailSettingsCard(
                      key: ValueKey(right[i].fieldKey),
                      field: right[i],
                      onChanged: onChanged,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductDetailSettingsCard extends StatefulWidget {
  const _ProductDetailSettingsCard({
    super.key,
    required this.field,
    required this.onChanged,
  });

  final CompanyProductField field;
  final ValueChanged<CompanyProductField> onChanged;

  @override
  State<_ProductDetailSettingsCard> createState() =>
      _ProductDetailSettingsCardState();
}

class _ProductDetailSettingsCardState
    extends State<_ProductDetailSettingsCard> {
  late bool _configureOpen;

  CompanyProductField get field => widget.field;

  bool get _needsOptions => field.isSelect;

  @override
  void initState() {
    super.initState();
    _configureOpen = field.enabled && _needsOptions;
  }

  @override
  void didUpdateWidget(covariant _ProductDetailSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (field.enabled && !oldWidget.field.enabled) {
      _configureOpen = _needsOptions;
    } else if (!field.enabled && oldWidget.field.enabled) {
      _configureOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final help = field.definition.helpText?.trim();
    final typeLabel = field.definition.fieldType.label;

    return AnimatedContainer(
      duration: AppDurations.normal,
      curve: AppCurves.standard,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelloFieldLabel(
                      label: field.label,
                      hint: help,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Enable',
                child: SizedBox(
                  height: 28,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch.adaptive(
                      value: field.enabled,
                      onChanged: (value) => widget.onChanged(
                        field.copyWith(
                          enabled: value,
                          required: value ? field.required : false,
                        ),
                      ),
                      activeThumbColor: AppColors.onPrimary,
                      activeTrackColor: context.brandAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (field.enabled) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _configureOpen = !_configureOpen),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      'Configure',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _configureOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: AppDurations.normal,
              curve: AppCurves.standard,
              alignment: Alignment.topCenter,
              child: _configureOpen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: AppColors.outlinePanel),
                        const SizedBox(height: 10),
                        _LabeledOptionRow(
                          label: 'Required',
                          tooltip:
                              'Users must provide this value before saving a product.',
                          trailing: SizedBox(
                            height: 28,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Switch.adaptive(
                                value: field.required,
                                onChanged: (value) => widget.onChanged(
                                  field.copyWith(required: value),
                                ),
                                activeThumbColor: AppColors.onPrimary,
                                activeTrackColor: context.brandAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Display',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _DisplayCheckRow(
                          label: 'List',
                          tooltip: 'Display this detail in product tables.',
                          value: field.showInList,
                          onChanged: (value) => widget.onChanged(
                            field.copyWith(showInList: value),
                          ),
                        ),
                        _DisplayCheckRow(
                          label: 'Catalog',
                          tooltip:
                              'Display this detail in the Sales Rep catalog.',
                          value: field.showInCatalog,
                          onChanged: (value) => widget.onChanged(
                            field.copyWith(showInCatalog: value),
                          ),
                        ),
                        if (field.isSelect) ...[
                          const SizedBox(height: 12),
                          _DropdownOptionsEditor(
                            field: field,
                            onChanged: widget.onChanged,
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

class _DropdownOptionsEditor extends StatefulWidget {
  const _DropdownOptionsEditor({required this.field, required this.onChanged});

  final CompanyProductField field;
  final ValueChanged<CompanyProductField> onChanged;

  @override
  State<_DropdownOptionsEditor> createState() => _DropdownOptionsEditorState();
}

class _DropdownOptionsEditorState extends State<_DropdownOptionsEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    final current = List<String>.from(widget.field.effectiveOptions);
    if (current.any((o) => o.toLowerCase() == value.toLowerCase())) {
      _controller.clear();
      return;
    }
    current.add(value);
    widget.onChanged(widget.field.copyWith(optionsOverride: current));
    _controller.clear();
  }

  void _remove(String option) {
    final current = List<String>.from(widget.field.effectiveOptions)
      ..remove(option);
    widget.onChanged(
      current.isEmpty
          ? widget.field.copyWith(clearOptionsOverride: true)
          : widget.field.copyWith(optionsOverride: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.field.effectiveOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Dropdown values',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              InputChip(
                label: Text(option),
                onDeleted: () => _remove(option),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Add a value',
                  isDense: true,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            SelloButton(
              label: 'Add',
              size: SelloButtonSize.small,
              variant: SelloButtonVariant.outline,
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}

class _LabeledOptionRow extends StatelessWidget {
  const _LabeledOptionRow({
    required this.label,
    required this.tooltip,
    required this.trailing,
  });

  final String label;
  final String tooltip;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: SelloFieldLabel(
            label: label,
            hint: tooltip,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    );
  }
}

class _DisplayCheckRow extends StatelessWidget {
  const _DisplayCheckRow({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String tooltip;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          InkWell(
            onTap: () => onChanged(!value),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: value,
                    onChanged: (next) => onChanged(next ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    activeColor: context.brandAccent,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SelloInfoHint(message: tooltip, semanticsLabel: 'About $label'),
        ],
      ),
    );
  }
}

class _OrdersInvoicesSection extends StatelessWidget {
  const _OrdersInvoicesSection({
    required this.state,
    required this.onChanged,
    required this.onSave,
    required this.onDiscard,
  });

  final HubSettingsState state;
  final void Function(CompanySettings Function(CompanySettings)) onChanged;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final draft = state.effective;
    final outstandingPolicy = draft.financialVisibility.outstandingBalance;
    final showSalesGate =
        outstandingPolicy == FinancialVisibilityPolicy.internalOnly;

    return SettingsSectionScaffold(
      actionBar: SettingsActionBar(
        enabled: state.isDirty,
        saving: state.isSaving,
        onSave: onSave,
        onDiscard: onDiscard,
      ),
      body: SettingsGroupCard(
        title: 'Orders & Invoices',
        description:
            'Customer-facing document behaviour. Internal visibility stays separate.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSubgroup(
              title: 'Customer financial visibility',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final kind
                      in FinancialVisibilityPolicies.configuredKinds) ...[
                    SettingsCompactField(
                      label: kind.label,
                      helper: draft.financialVisibility
                          .policyFor(kind)
                          .description,
                      child: SelloDropdown<FinancialVisibilityPolicy>(
                        value: draft.financialVisibility.policyFor(kind),
                        items: [
                          for (final policy in FinancialVisibilityPolicy.values)
                            DropdownMenuItem(
                              value: policy,
                              child: Text(policy.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          onChanged(
                            (c) => c.copyWith(
                              financialVisibility: c.financialVisibility
                                  .copyWithPolicy(kind: kind, policy: value),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (showSalesGate)
                    SelloStatusToggle(
                      value: draft.salesRepsCanViewOutstandingBalances,
                      label: 'Sales reps can view outstanding balances',
                      helper:
                          'Applies when visibility is Internal only. Sales Home shows '
                          'Collection Due and visit balances when enabled.',
                      onChanged: (value) => onChanged(
                        (c) => c.copyWith(
                          salesRepsCanViewOutstandingBalances: value,
                        ),
                      ),
                    )
                  else
                    Text(
                      outstandingPolicy == FinancialVisibilityPolicy.never
                          ? 'Outstanding balances are hidden everywhere, including Sales.'
                          : 'Customer copy is on — Sales Reps can see outstanding '
                                'balances so they match invoices and confirmations.',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Divider(height: 1, color: AppColors.outlinePanel),
            const SizedBox(height: 22),
            SettingsSubgroup(
              title: 'Collection approval',
              child: SettingsCompactField(
                label: 'Collection approval',
                helper:
                    'Require owner or manager approval before collections update customer balances.',
                child: SelloDropdown<CollectionApprovalMode>(
                  value: CollectionApprovalMode.fromRequired(
                    draft.collectionApprovalRequired,
                  ),
                  items: [
                    for (final mode in CollectionApprovalMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    onChanged(
                      (c) => c.copyWith(
                        collectionApprovalRequired: value.requiresApproval,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel({required this.section});

  final SettingsSectionId section;

  String get _title => switch (section) {
    SettingsSectionId.appearance => 'Appearance',
    SettingsSectionId.company => 'Company',
    SettingsSectionId.permissions => 'Access & permissions',
    SettingsSectionId.business ||
    SettingsSectionId.branding ||
    SettingsSectionId.inventory ||
    SettingsSectionId.productFields ||
    SettingsSectionId.ordersInvoices ||
    SettingsSectionId.notifications ||
    SettingsSectionId.reliability ||
    SettingsSectionId.about => 'Coming soon',
  };

  String get _message => switch (section) {
    SettingsSectionId.appearance =>
      'Theme and density controls will land in a later phase.',
    SettingsSectionId.company =>
      'Company profile, branches, and legal details are coming soon.',
    SettingsSectionId.permissions =>
      'Custom roles, permission templates, and temporary access will be '
          'managed here. Today, access follows Owner / Manager / Sales Rep.',
    SettingsSectionId.business ||
    SettingsSectionId.branding ||
    SettingsSectionId.inventory ||
    SettingsSectionId.productFields ||
    SettingsSectionId.ordersInvoices ||
    SettingsSectionId.notifications ||
    SettingsSectionId.reliability ||
    SettingsSectionId.about => 'This section is on the roadmap.',
  };

  @override
  Widget build(BuildContext context) {
    return SettingsSectionScaffold(
      body: SettingsGroupCard(
        title: _title,
        description: _message,
        child: const Text(
          'Coming soon',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textFaint,
          ),
        ),
      ),
    );
  }
}
