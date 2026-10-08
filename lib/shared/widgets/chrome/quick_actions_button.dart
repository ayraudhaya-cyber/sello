import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/quick_actions/quick_actions_launcher.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/quick_action.dart';

/// Visual treatment for [QuickActionsButton].
enum QuickActionsButtonStyle {
  /// Purple chip with label — Hub / Sales desktop top bar.
  labeled,

  /// Purple bolt icon — dense tablet chrome.
  compact,

  /// Hamburger in the Sales mobile app bar.
  menu,
}

/// Hub / Sales top-bar entry for the Quick Actions workspace.
///
/// Lightweight popup — launches shared dialogs / `?new=1` routes via
/// [QuickActionsLauncher]. Architecture leaves room for role, context, and
/// recently-used ranking later.
class QuickActionsButton extends ConsumerWidget {
  const QuickActionsButton({super.key, this.compact = false, this.style});

  /// Icon-only for dense mobile chrome. Ignored when [style] is set.
  final bool compact;

  /// Explicit style. Defaults from [compact] when null.
  final QuickActionsButtonStyle? style;

  QuickActionsButtonStyle get _style =>
      style ??
      (compact
          ? QuickActionsButtonStyle.compact
          : QuickActionsButtonStyle.labeled);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final actions = QuickActionsCatalog.forRole(session.appRole);
    if (actions.isEmpty) return const SizedBox.shrink();

    List<PopupMenuEntry<QuickActionId>> items(BuildContext context) => [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0 && _sectionBreak(actions[i - 1].id, actions[i].id))
          const PopupMenuDivider(height: 8),
        PopupMenuItem<QuickActionId>(
          value: actions[i].id,
          child: _QuickActionRow(action: actions[i]),
        ),
      ],
    ];

    if (_style == QuickActionsButtonStyle.menu) {
      return _QuickActionsMenuButton(
        actions: actions,
        onSelected: (id) => QuickActionsLauncher.launch(context, ref, id),
      );
    }

    return PopupMenuButton<QuickActionId>(
      tooltip: 'Quick Actions',
      offset: const Offset(0, 8),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      onSelected: (id) {
        QuickActionsLauncher.launch(context, ref, id);
      },
      itemBuilder: items,
      child: _style == QuickActionsButtonStyle.compact
          ? const _CompactChip()
          : const _LabeledChip(),
    );
  }

  static bool _sectionBreak(QuickActionId previous, QuickActionId next) {
    const create = {
      QuickActionId.newCustomer,
      QuickActionId.newProduct,
      QuickActionId.newSupplier,
      QuickActionId.newEmployee,
    };
    const ops = {
      QuickActionId.scheduleVisit,
      QuickActionId.receivePayment,
      QuickActionId.stockAdjustment,
      QuickActionId.startVisit,
      QuickActionId.newWalkIn,
      QuickActionId.newOrder,
      QuickActionId.logVisit,
    };
    if (create.contains(previous) && ops.contains(next)) return true;
    // Sales: create at end after field actions
    if (previous == QuickActionId.logVisit &&
        next == QuickActionId.newCustomer) {
      return true;
    }
    // Hub: optional order after stock ops
    if (previous == QuickActionId.stockAdjustment &&
        next == QuickActionId.newOrder) {
      return true;
    }
    return false;
  }
}

/// Sales mobile hamburger. Shows a close icon while the menu is open and uses
/// roomier rows than the desktop popup, since it is tapped with a thumb.
class _QuickActionsMenuButton extends StatefulWidget {
  const _QuickActionsMenuButton({
    required this.actions,
    required this.onSelected,
  });

  final List<QuickActionDefinition> actions;
  final ValueChanged<QuickActionId> onSelected;

  @override
  State<_QuickActionsMenuButton> createState() =>
      _QuickActionsMenuButtonState();
}

class _QuickActionsMenuButtonState extends State<_QuickActionsMenuButton> {
  bool _open = false;

  void _setOpen(bool value) {
    if (mounted && _open != value) setState(() => _open = value);
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    final width = (MediaQuery.sizeOf(context).width - 24).clamp(260.0, 360.0);
    return PopupMenuButton<QuickActionId>(
      tooltip: _open ? 'Close menu' : 'Quick Actions',
      offset: const Offset(0, 8),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      constraints: BoxConstraints(minWidth: width, maxWidth: width),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      onOpened: () => _setOpen(true),
      onCanceled: () => _setOpen(false),
      onSelected: (id) {
        _setOpen(false);
        widget.onSelected(id);
      },
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0 &&
              QuickActionsButton._sectionBreak(
                actions[i - 1].id,
                actions[i].id,
              ))
            const PopupMenuDivider(height: 12),
          PopupMenuItem<QuickActionId>(
            value: actions[i].id,
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _QuickActionRow(action: actions[i], large: true),
          ),
        ],
      ],
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          _open ? Icons.close_rounded : Icons.menu_rounded,
          key: ValueKey(_open),
        ),
      ),
    );
  }
}

class _LabeledChip extends StatelessWidget {
  const _LabeledChip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brandAccent,
      borderRadius: BorderRadius.circular(10),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Quick Actions',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactChip extends StatelessWidget {
  const _CompactChip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brandAccent,
      borderRadius: BorderRadius.circular(10),
      child: const SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({required this.action, this.large = false});

  final QuickActionDefinition action;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (large)
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.brandAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(action.icon, size: 21, color: context.brandAccent),
          )
        else
          Icon(action.icon, size: 20, color: context.brandAccent),
        SizedBox(width: large ? 14 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action.label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: large ? 15 : 13.5,
                ),
              ),
              if (action.subtitle != null) ...[
                if (large) const SizedBox(height: 2),
                Text(
                  action.subtitle!,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: large ? 12.5 : 11.5,
                    height: 1.3,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action.shortcutLabel != null && !large) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.outlineSubtle),
            ),
            child: Text(
              'Alt ${action.shortcutLabel!}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Desktop keyboard shortcuts for Quick Actions: Alt + the letter shown in
/// the menu (e.g. Alt+O for New Order). Only fires while focus is inside
/// [child], so open dialogs do not stack a second flow on top.
class QuickActionsShortcuts extends ConsumerWidget {
  const QuickActionsShortcuts({super.key, required this.child});

  final Widget child;

  static LogicalKeyboardKey? _keyFor(String label) => switch (label) {
    'C' => LogicalKeyboardKey.keyC,
    'M' => LogicalKeyboardKey.keyM,
    'O' => LogicalKeyboardKey.keyO,
    'P' => LogicalKeyboardKey.keyP,
    'V' => LogicalKeyboardKey.keyV,
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final actions = session == null
        ? const <QuickActionDefinition>[]
        : QuickActionsCatalog.forRole(session.appRole);
    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final action in actions) {
      final key = action.shortcutLabel == null
          ? null
          : _keyFor(action.shortcutLabel!);
      if (key == null) continue;
      bindings[SingleActivator(key, alt: true)] = () =>
          QuickActionsLauncher.launch(context, ref, action.id);
    }
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );
  }
}
