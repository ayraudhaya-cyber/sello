import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/media/media_processor.dart';
import 'package:sello/shared/widgets/inputs/sello_color_field.dart';
import 'package:flutter/material.dart';

void main() {
  group('MediaProcessor.codecTargets', () {
    test('does not pass both edges — that would squash the image', () {
      final wide = MediaProcessor.codecTargets(
        sourceWidth: 2000,
        sourceHeight: 400,
        maxEdge: 1000,
      );
      expect(wide.width, 1000);
      expect(wide.height, isNull);

      final tall = MediaProcessor.codecTargets(
        sourceWidth: 400,
        sourceHeight: 2000,
        maxEdge: 1000,
      );
      expect(tall.width, isNull);
      expect(tall.height, 1000);
    });

    test('leaves already-small images at native size', () {
      final targets = MediaProcessor.codecTargets(
        sourceWidth: 800,
        sourceHeight: 200,
        maxEdge: 1000,
      );
      expect(targets.width, isNull);
      expect(targets.height, isNull);
    });
  });

  test('SelloColorField hexOf writes canonical #RRGGBB', () {
    expect(SelloColorField.hexOf(const Color(0xFFDFBA39)), '#DFBA39');
    expect(SelloColorField.hexOf(const Color(0xFF0B6E4F)), '#0B6E4F');
  });
}
