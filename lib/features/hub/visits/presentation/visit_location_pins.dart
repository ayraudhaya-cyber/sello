import 'package:sello/shared/models/customer_visit.dart';

/// A stored visit coordinate. Labels are fixed and not user input.
class VisitLocationPin {
  const VisitLocationPin({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

/// Start and end pins already stored on the visit. Missing coordinates are omitted.
List<VisitLocationPin> visitLocationPins(CustomerVisit visit) {
  return [
    if (visit.hasStartGps)
      VisitLocationPin(
        label: 'Start',
        latitude: visit.startLatitude!,
        longitude: visit.startLongitude!,
      ),
    if (visit.hasEndGps)
      VisitLocationPin(
        label: 'End',
        latitude: visit.endLatitude!,
        longitude: visit.endLongitude!,
      ),
  ];
}

/// OpenStreetMap page centered on one pin, with no route.
Uri visitLocationExternalUri(VisitLocationPin pin) {
  return Uri(
    scheme: 'https',
    host: 'www.openstreetmap.org',
    path: '/',
    queryParameters: {
      'mlat': pin.latitude.toString(),
      'mlon': pin.longitude.toString(),
    },
    fragment: 'map=16/${pin.latitude}/${pin.longitude}',
  );
}

/// Tiny Leaflet page so one or two stored pins can share one map.
String visitLocationMapHtml(List<VisitLocationPin> pins) {
  final markers = pins
      .map(
        (pin) =>
            'L.marker([${pin.latitude}, ${pin.longitude}]).addTo(map).bindPopup(${_jsString(pin.label)});',
      )
      .join('\n');
  final points = pins
      .map((pin) => '[${pin.latitude}, ${pin.longitude}]')
      .join(',');
  final frame = pins.length <= 1
      ? 'map.setView([${pins.first.latitude}, ${pins.first.longitude}], 16);'
      : 'map.fitBounds([$points], {padding: [28, 28], maxZoom: 16});';
  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html, body, #map { margin: 0; height: 100%; width: 100%; }
  .leaflet-control-attribution { font-size: 10px; }
</style>
</head>
<body>
<div id="map"></div>
<script>
var map = L.map('map', { zoomControl: true });
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19,
  attribution: '&copy; OpenStreetMap'
}).addTo(map);
$markers
$frame
</script>
</body>
</html>
''';
}

String _jsString(String value) {
  return "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
}
