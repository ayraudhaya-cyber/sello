/// ISO 3166-1 alpha-2 countries with flag emoji for Made In Country.
class CountryOption {
  const CountryOption({
    required this.code,
    required this.name,
    required this.flag,
  });

  final String code;
  final String name;
  final String flag;

  String get label => '$flag $name';
}

abstract final class CountryCatalog {
  static const List<CountryOption> all = [
    CountryOption(code: 'LK', name: 'Sri Lanka', flag: '🇱🇰'),
    CountryOption(code: 'IN', name: 'India', flag: '🇮🇳'),
    CountryOption(code: 'CN', name: 'China', flag: '🇨🇳'),
    CountryOption(code: 'US', name: 'United States', flag: '🇺🇸'),
    CountryOption(code: 'GB', name: 'United Kingdom', flag: '🇬🇧'),
    CountryOption(code: 'DE', name: 'Germany', flag: '🇩🇪'),
    CountryOption(code: 'IT', name: 'Italy', flag: '🇮🇹'),
    CountryOption(code: 'JP', name: 'Japan', flag: '🇯🇵'),
    CountryOption(code: 'KR', name: 'South Korea', flag: '🇰🇷'),
    CountryOption(code: 'TW', name: 'Taiwan', flag: '🇹🇼'),
    CountryOption(code: 'TH', name: 'Thailand', flag: '🇹🇭'),
    CountryOption(code: 'VN', name: 'Vietnam', flag: '🇻🇳'),
    CountryOption(code: 'MY', name: 'Malaysia', flag: '🇲🇾'),
    CountryOption(code: 'SG', name: 'Singapore', flag: '🇸🇬'),
    CountryOption(code: 'AE', name: 'United Arab Emirates', flag: '🇦🇪'),
    CountryOption(code: 'TR', name: 'Turkey', flag: '🇹🇷'),
    CountryOption(code: 'ID', name: 'Indonesia', flag: '🇮🇩'),
    CountryOption(code: 'BD', name: 'Bangladesh', flag: '🇧🇩'),
    CountryOption(code: 'PK', name: 'Pakistan', flag: '🇵🇰'),
    CountryOption(code: 'AU', name: 'Australia', flag: '🇦🇺'),
    CountryOption(code: 'CA', name: 'Canada', flag: '🇨🇦'),
    CountryOption(code: 'FR', name: 'France', flag: '🇫🇷'),
    CountryOption(code: 'ES', name: 'Spain', flag: '🇪🇸'),
    CountryOption(code: 'NL', name: 'Netherlands', flag: '🇳🇱'),
    CountryOption(code: 'PL', name: 'Poland', flag: '🇵🇱'),
    CountryOption(code: 'MX', name: 'Mexico', flag: '🇲🇽'),
    CountryOption(code: 'BR', name: 'Brazil', flag: '🇧🇷'),
    CountryOption(code: 'PH', name: 'Philippines', flag: '🇵🇭'),
    CountryOption(code: 'HK', name: 'Hong Kong', flag: '🇭🇰'),
    CountryOption(code: 'SA', name: 'Saudi Arabia', flag: '🇸🇦'),
  ];

  static CountryOption? byCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final normalized = code.trim().toUpperCase();
    for (final country in all) {
      if (country.code == normalized) return country;
    }
    return null;
  }

  static String display(String? code) {
    final match = byCode(code);
    if (match != null) return match.label;
    if (code == null || code.trim().isEmpty) return '—';
    return code.trim().toUpperCase();
  }

  static List<({String code, String label})> asSelectOptions() {
    return [
      for (final country in all) (code: country.code, label: country.label),
    ];
  }
}
