import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/quick_actions/quick_actions_launcher.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/quick_action.dart';

/// Hub / Sales top-bar entry for the Quick Actions workspace.
///
/// Lightweight popup — launches shared dialogs / `?new=1` routes via
/// [QuickActionsLauncher]. Architecture leaves room for role, context, and
/// recently-used ranking later.
class QuickActionsButton extends ConsumerWidget {
  const QuickActionsButton({
    super.key,
    this.compact = false,
  });

  /// Icon-only for dense mobile chrome.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final actions = QuickActionsCatalog.forRole(session.appRole);
    if (actions.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<QuickActionId>(
      tooltip: 'Quick Actions',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      onSelected: (id) {
        QuickActionsLauncher.launch(context, ref, id);
      },
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0 && _sectionBreak(actions[i - 1].id, actions[i].id))
            const PopupMenuDivider(height: 8),
          PopupMenuItem<QuickActionId>(
            value: actions[i].id,
            child: _QuickActionRow(action: actions[i]),
          ),
        ],
      ],
      child: compact ? const _CompactChip() : const _LabeledChip(),
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
  const _QuickActionRow({required this.action});

  final QuickActionDefinition action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(action.icon, size: 20, color: context.brandAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action.label,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              if (action.subtitle != null)
                Text(
                  action.subtitle!,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
        if (action.shortcutLabel != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.outlineSubtle),
            ),
            child: Text(
              action.shortcutLabel!,
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

/// Reserved host for a future Cmd/Ctrl+K command palette.
class QuickActionsShortcuts extends ConsumerWidget {
  const QuickActionsShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: const {
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): _noop,
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _noop,
      },
      child: Focus(autofocus: false, child: child),
    );
  }

  static void _noop() {}
}
