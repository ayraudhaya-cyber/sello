import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:sello/shared/widgets/feedback/sello_activity_timeline.dart';

/// Loads company activity for an entity and renders [SelloActivityTimeline].
///
/// Reuse on Customer / Product / Order / Supplier / Team surfaces — do not
/// invent module-specific activity lists for operational events.
class EntityActivityPanel extends ConsumerStatefulWidget {
  const EntityActivityPanel({
    super.key,
    required this.referenceType,
    required this.referenceId,
    this.emptyMessage = 'No activity yet for this record.',
    this.limit = 30,
    this.dense = true,
  });

  final String referenceType;
  final String referenceId;
  final String emptyMessage;
  final int limit;
  final bool dense;

  @override
  ConsumerState<EntityActivityPanel> createState() =>
      _EntityActivityPanelState();
}

class _EntityActivityPanelState extends ConsumerState<EntityActivityPanel> {
  List<CompanyActivityEvent> _events = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant EntityActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.referenceId != widget.referenceId ||
        oldWidget.referenceType != widget.referenceType) {
      _load();
    }
  }

  Future<void> _load() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final events =
          await ref.read(notificationRepositoryProvider).fetchCompanyActivity(
                companyId: session.company.id,
                referenceType: widget.referenceType,
                referenceId: widget.referenceId,
                limit: widget.limit,
              );
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return SelloActivityTimeline(
      events: _events,
      emptyMessage: widget.emptyMessage,
      dense: widget.dense,
    );
  }
}
