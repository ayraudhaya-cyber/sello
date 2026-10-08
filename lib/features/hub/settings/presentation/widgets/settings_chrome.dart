import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive_layout.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Shared Settings chrome. Business, Branding, and Product Details are the
/// layout reference: grouped cards, compact fields, two-up where it helps,
/// progressive disclosure, and one sticky [SettingsActionBar] when the page
/// has a draft.

const double _settingsLabelSlotHeight = 22;

/// Soft settings card with title, optional description, and body fields.
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.footer,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      enableHoverLift: false,
      elevation: SelloCardElevation.soft,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      borderRadius: AppRadius.panelAll,
      borderColor: AppColors.outlinePanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 22),
          child,
          if (footer != null) ...[const SizedBox(height: 24), footer!],
        ],
      ),
    );
  }
}

/// Label + control used inside settings cards.
///
/// [helper] is secondary explanation on [SelloInfoHint], not body copy —
/// never use it to say “Optional”. Mark required fields with [required].
class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.required = false,
    this.compact = false,
  });

  final String label;

  /// Secondary explanation shown via [SelloInfoHint] beside the label.
  final String? helper;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _settingsLabelSlotHeight,
          child: SelloFieldLabel(
            label: label,
            hint: helper,
            required: required,
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        child,
      ],
    );
  }
}

class SettingsSaveBar extends StatelessWidget {
  const SettingsSaveBar({
    super.key,
    required this.enabled,
    required this.saving,
    required this.onSave,
    this.onDiscard,
    this.leading,
  });

  final bool enabled;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ?leading,
        const Spacer(),
        if (onDiscard != null) ...[
          SelloButton(
            label: 'Discard',
            variant: SelloButtonVariant.ghost,
            onPressed: enabled && !saving ? onDiscard : null,
          ),
          const SizedBox(width: 8),
        ],
        SelloButton(
          label: saving ? 'Saving…' : 'Save changes',
          onPressed: enabled && !saving ? onSave : null,
        ),
      ],
    );
  }
}

/// Sticky full-width save / discard footer. Hidden until the section has a
/// draft ([enabled]) or a save is in flight.
class SettingsActionBar extends StatelessWidget {
  const SettingsActionBar({
    super.key,
    required this.enabled,
    required this.saving,
    required this.onSave,
    this.onDiscard,
    this.leading,
  });

  final bool enabled;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final visible = enabled || saving;
    return AnimatedSwitcher(
      duration: AppDurations.fast,
      switchInCurve: AppCurves.standard,
      switchOutCurve: AppCurves.standard,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
      child: visible
          ? DecoratedBox(
              key: const ValueKey('settings-action-bar'),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border(
                  top: BorderSide(color: AppColors.outlinePanel),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C4FF2).withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
                  child: SettingsSaveBar(
                    enabled: enabled,
                    saving: saving,
                    onSave: onSave,
                    onDiscard: onDiscard,
                    leading: leading,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('settings-action-bar-hidden')),
    );
  }
}

/// Fills the settings content pane: scrolling body + optional sticky footer.
class SettingsSectionScaffold extends StatelessWidget {
  const SettingsSectionScaffold({
    super.key,
    required this.body,
    this.actionBar,
  });

  final Widget body;
  final Widget? actionBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: body,
          ),
        ),
        ?actionBar,
      ],
    );
  }
}

/// Two related controls side-by-side on wide screens, stacked when narrow.
class SettingsTwoUp extends StatelessWidget {
  const SettingsTwoUp({super.key, required this.children, this.spacing = 16});

  final List<Widget> children;
  final double spacing;

  static const _minItemWidth = ResponsiveLayout.formFieldMinWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = !ResponsiveLayout.canFitRow(
          width: constraints.maxWidth,
          itemCount: children.length,
          minItemWidth: _minItemWidth,
          gap: spacing,
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Label (with optional info hint) above a compact control.
class SettingsCompactField extends StatelessWidget {
  const SettingsCompactField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.required = false,
  });

  final String label;

  /// Secondary explanation shown via [SelloInfoHint] beside the label.
  /// Never use this to say “Optional”.
  final String? helper;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _settingsLabelSlotHeight,
          child: SelloFieldLabel(
            label: label,
            hint: helper,
            required: required,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// Quiet heading for a cluster of fields inside a settings card.
class SettingsSubgroup extends StatelessWidget {
  const SettingsSubgroup({
    super.key,
    required this.title,
    required this.child,
    this.helper,
  });

  final String title;
  final Widget child;

  /// Shown via [SelloInfoHint] beside the title.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _settingsLabelSlotHeight,
          child: Row(
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
              if (helper != null && helper!.trim().isNotEmpty) ...[
                const SizedBox(width: 6),
                SelloInfoHint(message: helper!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Progressive disclosure for advanced or reserved options.
class SettingsExpandable extends StatefulWidget {
  const SettingsExpandable({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.initiallyExpanded = false,
    this.panel = false,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool initiallyExpanded;

  /// Renders as a bordered, rounded panel that clearly reads as a control
  /// (leading [icon], chevron chip, divider before the content).
  final bool panel;
  final IconData? icon;

  @override
  State<SettingsExpandable> createState() => _SettingsExpandableState();
}

class _SettingsExpandableState extends State<SettingsExpandable> {
  late bool _open = widget.initiallyExpanded;

  Widget _buildPanel() {
    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: _open
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.outlineStrong,
        ),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.mdAll,
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                hoverColor: AppColors.surfaceSelected.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (widget.icon != null) ...[
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.icon,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle!,
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _open
                              ? AppColors.primaryContainer
                              : AppColors.surfaceMuted,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.outlinePanel),
                        ),
                        child: AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: AppDurations.fast,
                          curve: AppCurves.standard,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: _open
                                ? AppColors.primary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppDurations.fast,
                curve: AppCurves.standard,
                alignment: Alignment.topCenter,
                child: _open
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(
                            height: 1,
                            color: AppColors.outlinePanel,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: widget.child,
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.panel) return _buildPanel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppDurations.fast,
          curve: AppCurves.standard,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Even/odd split into two columns on wide screens; a single column when narrow.
class SettingsTwoColumn extends StatelessWidget {
  const SettingsTwoColumn({super.key, required this.children, this.gap = 12});

  final List<Widget> children;
  final double gap;

  static const _minItemWidth = ResponsiveLayout.formFieldMinWidth;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            children.length == 1 ||
            !ResponsiveLayout.canFitRow(
              width: constraints.maxWidth,
              itemCount: 2,
              minItemWidth: _minItemWidth,
              gap: gap,
            );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }

        final left = <Widget>[];
        final right = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          (i.isEven ? left : right).add(children[i]);
        }

        Widget column(List<Widget> items) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                items[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: column(left)),
            SizedBox(width: gap),
            Expanded(child: column(right)),
          ],
        );
      },
    );
  }
}

/// Compact label + switch row for preference lists.
class SettingsPreferenceRow extends StatelessWidget {
  const SettingsPreferenceRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.enabled = true,
  });

  final String label;
  final String? helper;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (helper != null && helper!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  helper!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        SelloSwitch(
          value: value,
          onChanged: enabled ? onChanged : null,
          enabled: enabled,
        ),
      ],
    );
  }
}

/// Left-rail navigation for settings sections, or a horizontally scrolling
/// tab strip when [axis] is [Axis.horizontal].
class SettingsSideNav extends StatelessWidget {
  const SettingsSideNav({
    super.key,
    required this.sections,
    required this.selected,
    required this.onSelect,
    this.axis = Axis.vertical,
  });

  final List<({String id, String label, IconData icon, bool comingSoon})>
  sections;
  final String selected;
  final ValueChanged<String> onSelect;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final section in sections)
        _SettingsNavTile(
          label: section.label,
          icon: section.icon,
          selected: section.id == selected,
          comingSoon: section.comingSoon,
          compact: axis == Axis.horizontal,
          onTap: () => onSelect(section.id),
        ),
    ];

    return SelloCard(
      enableHoverLift: false,
      elevation: SelloCardElevation.soft,
      padding: axis == Axis.horizontal
          ? const EdgeInsets.symmetric(vertical: 8, horizontal: 8)
          : const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      borderRadius: AppRadius.panelAll,
      borderColor: AppColors.outlinePanel,
      child: axis == Axis.horizontal
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: tiles),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: tiles,
            ),
    );
  }
}

class _SettingsNavTile extends StatefulWidget {
  const _SettingsNavTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.comingSoon,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool comingSoon;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_SettingsNavTile> createState() => _SettingsNavTileState();
}

class _SettingsNavTileState extends State<_SettingsNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final accent = Theme.of(context).colorScheme.primary;
    final fg = selected
        ? accent
        : (_hovered ? AppColors.textPrimary : AppColors.textSecondary);
    final bg = selected
        ? accent.withValues(alpha: 0.08)
        : (_hovered ? AppColors.surfaceMuted : Colors.transparent);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: widget.compact ? 0 : 2,
        horizontal: widget.compact ? 2 : 0,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            hoverColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 12 : 12,
                vertical: widget.compact ? 8 : 11,
              ),
              child: Row(
                mainAxisSize: widget.compact
                    ? MainAxisSize.min
                    : MainAxisSize.max,
                children: [
                  Icon(widget.icon, size: 18, color: fg),
                  const SizedBox(width: 10),
                  if (widget.compact)
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: fg,
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                  if (widget.comingSoon) ...[
                    const SizedBox(width: 8),
                    Text(
                      'Soon',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Digits-only formatter for integer settings fields.
class NonNegativeIntegerFormatter extends TextInputFormatter {
  const NonNegativeIntegerFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (RegExp(r'^\d+$').hasMatch(text)) return newValue;
    return oldValue;
  }
}
