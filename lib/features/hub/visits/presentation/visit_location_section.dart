import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/visits/presentation/visit_location_map_body.dart';
import 'package:sello/features/hub/visits/presentation/visit_location_pins.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:url_launcher/url_launcher.dart';

/// Supplementary start/end location. Missing coordinates stay quiet.
class VisitLocationSection extends StatelessWidget {
  const VisitLocationSection({super.key, required this.visit});

  final CustomerVisit visit;

  @override
  Widget build(BuildContext context) {
    final pins = visitLocationPins(visit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Location',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Location is recorded when available.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            height: 1.35,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(height: 8),
        _LocationRow(
          label: 'Start location',
          captured: visit.hasStartGps,
          onView: visit.hasStartGps ? () => _openMap(context, pins) : null,
        ),
        const SizedBox(height: 4),
        _LocationRow(
          label: 'End location',
          captured: visit.hasEndGps,
          onView: visit.hasEndGps ? () => _openMap(context, pins) : null,
        ),
      ],
    );
  }

  void _openMap(BuildContext context, List<VisitLocationPin> pins) {
    showDialog<void>(
      context: context,
      builder: (context) => _VisitLocationDialog(pins: pins),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.label,
    required this.captured,
    required this.onView,
  });

  final String label;
  final bool captured;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          captured ? 'Captured' : 'Not captured',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            color: AppColors.textTertiary,
          ),
        ),
        if (captured && onView != null)
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: context.brandAccent,
            ),
            child: const Text('View on map'),
          ),
      ],
    );
  }
}

class _VisitLocationDialog extends StatelessWidget {
  const _VisitLocationDialog({required this.pins});

  final List<VisitLocationPin> pins;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.panelAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Visit location',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (pins.length > 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Start and end locations.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.outlinePanel),
                  ),
                  child: VisitLocationMapBody(pins: pins),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  for (final pin in pins)
                    TextButton(
                      onPressed: () => launchUrl(
                        visitLocationExternalUri(pin),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text('Open ${pin.label.toLowerCase()} on map'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
