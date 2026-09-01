import 'package:geolocator/geolocator.dart';

/// Named locality with approximate centre — used to rank Area / suburb picks
/// near the rep’s GPS without a Places API.
class SriLankaArea {
  const SriLankaArea({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;
}

/// Searchable Sri Lanka areas / suburbs for field sales (walk-in, customers).
///
/// Dense around Colombo metro; major towns island-wide. Free-text still
/// allowed in the UI when a place is missing.
abstract final class SriLankaAreas {
  static const List<SriLankaArea> all = [
    // Colombo metro & suburbs
    SriLankaArea(name: 'Colombo 01 – Fort', latitude: 6.9344, longitude: 79.8428),
    SriLankaArea(name: 'Colombo 02 – Slave Island', latitude: 6.9219, longitude: 79.8481),
    SriLankaArea(name: 'Colombo 03 – Kollupitiya', latitude: 6.9022, longitude: 79.8532),
    SriLankaArea(name: 'Colombo 04 – Bambalapitiya', latitude: 6.8913, longitude: 79.8568),
    SriLankaArea(name: 'Colombo 05 – Havelock Town', latitude: 6.8831, longitude: 79.8656),
    SriLankaArea(name: 'Colombo 06 – Wellawatte', latitude: 6.8740, longitude: 79.8608),
    SriLankaArea(name: 'Colombo 07 – Cinnamon Gardens', latitude: 6.9103, longitude: 79.8648),
    SriLankaArea(name: 'Colombo 08 – Borella', latitude: 6.9147, longitude: 79.8776),
    SriLankaArea(name: 'Colombo 09 – Dematagoda', latitude: 6.9372, longitude: 79.8779),
    SriLankaArea(name: 'Colombo 10 – Maradana', latitude: 6.9278, longitude: 79.8612),
    SriLankaArea(name: 'Colombo 11 – Pettah', latitude: 6.9388, longitude: 79.8542),
    SriLankaArea(name: 'Colombo 12 – Hulftsdorp', latitude: 6.9395, longitude: 79.8618),
    SriLankaArea(name: 'Colombo 13 – Kotahena', latitude: 6.9503, longitude: 79.8635),
    SriLankaArea(name: 'Colombo 14 – Grandpass', latitude: 6.9485, longitude: 79.8752),
    SriLankaArea(name: 'Colombo 15 – Mattakkuliya', latitude: 6.9705, longitude: 79.8720),
    SriLankaArea(name: 'Dehiwala', latitude: 6.8560, longitude: 79.8651),
    SriLankaArea(name: 'Mount Lavinia', latitude: 6.8295, longitude: 79.8650),
    SriLankaArea(name: 'Ratmalana', latitude: 6.8220, longitude: 79.8862),
    SriLankaArea(name: 'Moratuwa', latitude: 6.7730, longitude: 79.8816),
    SriLankaArea(name: 'Panadura', latitude: 6.7133, longitude: 79.9042),
    SriLankaArea(name: 'Kalutara', latitude: 6.5854, longitude: 79.9607),
    SriLankaArea(name: 'Nugegoda', latitude: 6.8649, longitude: 79.8997),
    SriLankaArea(name: 'Maharagama', latitude: 6.8480, longitude: 79.9267),
    SriLankaArea(name: 'Kottawa', latitude: 6.8400, longitude: 79.9650),
    SriLankaArea(name: 'Piliyandala', latitude: 6.8018, longitude: 79.9227),
    SriLankaArea(name: 'Boralesgamuwa', latitude: 6.8410, longitude: 79.9006),
    SriLankaArea(name: 'Kohuwala', latitude: 6.8622, longitude: 79.8845),
    SriLankaArea(name: 'Nawala', latitude: 6.8954, longitude: 79.8889),
    SriLankaArea(name: 'Rajagiriya', latitude: 6.9095, longitude: 79.8916),
    SriLankaArea(name: 'Battaramulla', latitude: 6.9000, longitude: 79.9180),
    SriLankaArea(name: 'Pelawatte', latitude: 6.8890, longitude: 79.9340),
    SriLankaArea(name: 'Thalawathugoda', latitude: 6.8770, longitude: 79.9400),
    SriLankaArea(name: 'Kotte', latitude: 6.8905, longitude: 79.9015),
    SriLankaArea(name: 'Ethul Kotte', latitude: 6.8915, longitude: 79.9055),
    SriLankaArea(name: 'Malabe', latitude: 6.9063, longitude: 79.9690),
    SriLankaArea(name: 'Athurugiriya', latitude: 6.8730, longitude: 79.9890),
    SriLankaArea(name: 'Kaduwela', latitude: 6.9350, longitude: 79.9840),
    SriLankaArea(name: 'Homagama', latitude: 6.8440, longitude: 80.0020),
    SriLankaArea(name: 'Godagama', latitude: 6.8470, longitude: 80.0320),
    SriLankaArea(name: 'Kesbewa', latitude: 6.7950, longitude: 79.9380),
    SriLankaArea(name: 'Kirulapone', latitude: 6.8785, longitude: 79.8765),
    SriLankaArea(name: 'Narahenpita', latitude: 6.8930, longitude: 79.8770),
    SriLankaArea(name: 'Thimbirigasyaya', latitude: 6.8945, longitude: 79.8685),
    SriLankaArea(name: 'Bambalapitiya', latitude: 6.8913, longitude: 79.8568),
    SriLankaArea(name: 'Wellawatte', latitude: 6.8740, longitude: 79.8608),
    SriLankaArea(name: 'Kiribathgoda', latitude: 6.9785, longitude: 79.9295),
    SriLankaArea(name: 'Kelaniya', latitude: 6.9553, longitude: 79.9220),
    SriLankaArea(name: 'Peliyagoda', latitude: 6.9605, longitude: 79.8990),
    SriLankaArea(name: 'Wattala', latitude: 6.9890, longitude: 79.8910),
    SriLankaArea(name: 'Ja-Ela', latitude: 7.0742, longitude: 79.8919),
    SriLankaArea(name: 'Negombo', latitude: 7.2083, longitude: 79.8358),
    SriLankaArea(name: 'Katunayake', latitude: 7.1642, longitude: 79.8730),
    SriLankaArea(name: 'Seeduwa', latitude: 7.1320, longitude: 79.8850),
    SriLankaArea(name: 'Gampaha', latitude: 7.0917, longitude: 79.9990),
    SriLankaArea(name: 'Ragama', latitude: 7.0270, longitude: 79.9160),
    SriLankaArea(name: 'Kadawatha', latitude: 7.0010, longitude: 79.9520),
    SriLankaArea(name: 'Nittambuwa', latitude: 7.1440, longitude: 80.0960),
    SriLankaArea(name: 'Mirigama', latitude: 7.2330, longitude: 80.1270),
    SriLankaArea(name: 'Minuwangoda', latitude: 7.1730, longitude: 79.9530),
    SriLankaArea(name: 'Divulapitiya', latitude: 7.2200, longitude: 80.0150),
    SriLankaArea(name: 'Veyangoda', latitude: 7.1570, longitude: 80.0590),
    SriLankaArea(name: 'Avissawella', latitude: 6.9530, longitude: 80.2110),
    SriLankaArea(name: 'Hanwella', latitude: 6.9010, longitude: 80.0820),
    SriLankaArea(name: 'Padukka', latitude: 6.8470, longitude: 80.0900),
    SriLankaArea(name: 'Horana', latitude: 6.7150, longitude: 80.0620),
    SriLankaArea(name: 'Bandaragama', latitude: 6.7150, longitude: 79.9880),
    SriLankaArea(name: 'Beruwala', latitude: 6.4740, longitude: 79.9830),
    SriLankaArea(name: 'Aluthgama', latitude: 6.4320, longitude: 80.0000),
    SriLankaArea(name: 'Bentota', latitude: 6.4210, longitude: 80.0010),

    // Other major towns
    SriLankaArea(name: 'Kandy', latitude: 7.2906, longitude: 80.6337),
    SriLankaArea(name: 'Peradeniya', latitude: 7.2690, longitude: 80.5960),
    SriLankaArea(name: 'Katugastota', latitude: 7.3270, longitude: 80.6220),
    SriLankaArea(name: 'Gampola', latitude: 7.1640, longitude: 80.5690),
    SriLankaArea(name: 'Nuwara Eliya', latitude: 6.9497, longitude: 80.7891),
    SriLankaArea(name: 'Hatton', latitude: 6.8910, longitude: 80.5960),
    SriLankaArea(name: 'Galle', latitude: 6.0535, longitude: 80.2210),
    SriLankaArea(name: 'Unawatuna', latitude: 6.0100, longitude: 80.2480),
    SriLankaArea(name: 'Hikkaduwa', latitude: 6.1395, longitude: 80.1012),
    SriLankaArea(name: 'Matara', latitude: 5.9549, longitude: 80.5550),
    SriLankaArea(name: 'Tangalle', latitude: 6.0240, longitude: 80.7910),
    SriLankaArea(name: 'Hambantota', latitude: 6.1240, longitude: 81.1185),
    SriLankaArea(name: 'Kurunegala', latitude: 7.4867, longitude: 80.3647),
    SriLankaArea(name: 'Chilaw', latitude: 7.5750, longitude: 79.7950),
    SriLankaArea(name: 'Puttalam', latitude: 8.0362, longitude: 79.8283),
    SriLankaArea(name: 'Anuradhapura', latitude: 8.3114, longitude: 80.4037),
    SriLankaArea(name: 'Polonnaruwa', latitude: 7.9403, longitude: 81.0188),
    SriLankaArea(name: 'Trincomalee', latitude: 8.5874, longitude: 81.2152),
    SriLankaArea(name: 'Batticaloa', latitude: 7.7102, longitude: 81.6924),
    SriLankaArea(name: 'Kalmunai', latitude: 7.4090, longitude: 81.8350),
    SriLankaArea(name: 'Ampara', latitude: 7.2970, longitude: 81.6820),
    SriLankaArea(name: 'Jaffna', latitude: 9.6615, longitude: 80.0255),
    SriLankaArea(name: 'Vavuniya', latitude: 8.7510, longitude: 80.4970),
    SriLankaArea(name: 'Mannar', latitude: 8.9810, longitude: 79.9040),
    SriLankaArea(name: 'Ratnapura', latitude: 6.6828, longitude: 80.4012),
    SriLankaArea(name: 'Balangoda', latitude: 6.6500, longitude: 80.6850),
    SriLankaArea(name: 'Embilipitiya', latitude: 6.3430, longitude: 80.8490),
    SriLankaArea(name: 'Badulla', latitude: 6.9934, longitude: 81.0550),
    SriLankaArea(name: 'Bandarawela', latitude: 6.8290, longitude: 80.9980),
    SriLankaArea(name: 'Ella', latitude: 6.8667, longitude: 81.0466),
    SriLankaArea(name: 'Monaragala', latitude: 6.8720, longitude: 81.3510),
    SriLankaArea(name: 'Matale', latitude: 7.4675, longitude: 80.6234),
    SriLankaArea(name: 'Dambulla', latitude: 7.8742, longitude: 80.6517),
    SriLankaArea(name: 'Sigiriya', latitude: 7.9570, longitude: 80.7603),
    SriLankaArea(name: 'Kegalle', latitude: 7.2513, longitude: 80.3464),
    SriLankaArea(name: 'Mawanella', latitude: 7.2530, longitude: 80.4460),
    SriLankaArea(name: 'Warakapola', latitude: 7.2270, longitude: 80.2000),
  ];

  /// Names ranked nearest-first when [latitude]/[longitude] are known.
  static List<String> suggestionsNear({
    double? latitude,
    double? longitude,
    Iterable<String> extraNames = const [],
  }) {
    final ranked = List<SriLankaArea>.from(all);
    if (latitude != null && longitude != null) {
      ranked.sort((a, b) {
        final da = Geolocator.distanceBetween(
          latitude,
          longitude,
          a.latitude,
          a.longitude,
        );
        final db = Geolocator.distanceBetween(
          latitude,
          longitude,
          b.latitude,
          b.longitude,
        );
        return da.compareTo(db);
      });
    } else {
      ranked.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    final seen = <String>{};
    final out = <String>[];

    void add(String raw) {
      final name = raw.trim();
      if (name.isEmpty) return;
      final key = name.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(name);
    }

    // Prefer nearby curated list, then any company-specific extras.
    for (final area in ranked) {
      add(area.name);
    }
    for (final extra in extraNames) {
      add(extra);
    }
    return out;
  }
}
