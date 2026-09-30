import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/responsive/responsive_layout.dart';
import 'package:sello/core/theme/app_spacing.dart';

void main() {
  group('ResponsiveLayout.columnsFor', () {
    test('keeps five KPI cards on a wide content column', () {
      expect(
        ResponsiveLayout.columnsFor(
          width: 1200,
          itemCount: 5,
          gap: AppSpacing.md,
        ),
        5,
      );
    });

    test('drops columns before cards fall below the minimum width', () {
      expect(
        ResponsiveLayout.columnsFor(
          width: 900,
          itemCount: 5,
          gap: AppSpacing.md,
        ),
        4,
      );
      expect(
        ResponsiveLayout.columnsFor(
          width: 700,
          itemCount: 5,
          gap: AppSpacing.md,
        ),
        3,
      );
      expect(
        ResponsiveLayout.columnsFor(
          width: 500,
          itemCount: 5,
          gap: AppSpacing.md,
        ),
        2,
      );
    });

    test('uses a single column on small phones', () {
      expect(
        ResponsiveLayout.columnsFor(
          width: 360,
          itemCount: 5,
          gap: AppSpacing.md,
        ),
        1,
      );
    });

    test('never exceeds the number of items or maxColumns', () {
      expect(
        ResponsiveLayout.columnsFor(
          width: 1600,
          itemCount: 3,
          maxColumns: 5,
        ),
        3,
      );
      expect(
        ResponsiveLayout.columnsFor(
          width: 1600,
          itemCount: 8,
          maxColumns: 6,
        ),
        6,
      );
    });
  });

  group('ResponsiveLayout.canFitRow', () {
    test('stacks when equal children would be too narrow', () {
      expect(
        ResponsiveLayout.canFitRow(
          width: 500,
          itemCount: 2,
          minItemWidth: ResponsiveLayout.sectionCardMinWidth,
          gap: AppSpacing.gap,
        ),
        isFalse,
      );
      expect(
        ResponsiveLayout.canFitRow(
          width: 800,
          itemCount: 2,
          minItemWidth: ResponsiveLayout.sectionCardMinWidth,
          gap: AppSpacing.gap,
        ),
        isTrue,
      );
    });

    test('honours flex so a 32% pane is not squeezed', () {
      expect(
        ResponsiveLayout.canFitRow(
          width: 700,
          itemCount: 2,
          minItemWidth: ResponsiveLayout.sectionCardMinWidth,
          gap: AppSpacing.gap,
          flexes: const [68, 32],
        ),
        isFalse,
      );
      expect(
        ResponsiveLayout.canFitRow(
          width: 1100,
          itemCount: 2,
          minItemWidth: ResponsiveLayout.sectionCardMinWidth,
          gap: AppSpacing.gap,
          flexes: const [68, 32],
        ),
        isTrue,
      );
    });
  });

  group('ResponsiveLayout.chartHeight', () {
    test('clamps to a readable band instead of a tall empty box', () {
      expect(ResponsiveLayout.chartHeight(320), 140);
      expect(ResponsiveLayout.chartHeight(500), closeTo(140, 0.1));
      expect(ResponsiveLayout.chartHeight(900), closeTo(220, 0.1));
      expect(ResponsiveLayout.chartHeight(1600), 220);
    });
  });
}
