import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/hub/visits/presentation/visit_location_pins.dart';
import 'package:sello/shared/models/customer_visit.dart';

CustomerVisit _visit({
  double? startLat,
  double? startLng,
  double? endLat,
  double? endLng,
  CustomerVisitStatus status = CustomerVisitStatus.completed,
}) {
  return CustomerVisit(
    id: 'v1',
    companyId: 'c1',
    customerId: 'cust',
    employeeId: 'rep',
    status: status,
    startedAt: DateTime.utc(2026, 9, 28, 9),
    endedAt: DateTime.utc(2026, 9, 28, 9, 20),
    startLatitude: startLat,
    startLongitude: startLng,
    endLatitude: endLat,
    endLongitude: endLng,
  );
}

void main() {
  test('start GPS only keeps a single start pin', () {
    final pins = visitLocationPins(_visit(startLat: 6.9, startLng: 79.8));
    expect(pins, hasLength(1));
    expect(pins.single.label, 'Start');
    final html = visitLocationMapHtml(pins);
    expect(html, contains('6.9'));
    expect(html, contains('79.8'));
    expect(html, contains('Start'));
    expect(html, isNot(contains('End')));
  });

  test('start and end GPS share one map', () {
    final pins = visitLocationPins(
      _visit(startLat: 6.9, startLng: 79.8, endLat: 6.91, endLng: 79.86),
    );
    expect(pins.map((pin) => pin.label), ['Start', 'End']);
    final html = visitLocationMapHtml(pins);
    expect(html, contains('fitBounds'));
    expect(html, contains('Start'));
    expect(html, contains('End'));
  });

  test('missing GPS adds no pins and does not block a completed visit', () {
    final visit = _visit();
    expect(visit.hasStartGps, isFalse);
    expect(visit.hasEndGps, isFalse);
    expect(visit.isCompleted, isTrue);
    expect(visitLocationPins(visit), isEmpty);
  });
}
