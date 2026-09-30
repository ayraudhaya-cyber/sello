/// Licensed commercial and specialised banks commonly seen on Sri Lankan cheques.
const List<({String name, List<String> aliases})> kSriLankaBanks = [
  (name: 'Bank of Ceylon', aliases: ['BOC']),
  (name: "People's Bank", aliases: ['PB', 'Peoples Bank', "People's"]),
  (name: 'National Savings Bank', aliases: ['NSB']),
  (name: 'Commercial Bank of Ceylon', aliases: ['COMBANK', 'Commercial Bank']),
  (name: 'Hatton National Bank', aliases: ['HNB']),
  (name: 'Sampath Bank', aliases: ['SAMP']),
  (name: 'Seylan Bank', aliases: []),
  (name: 'NDB Bank', aliases: ['NDB', 'National Development Bank']),
  (name: 'DFCC Bank', aliases: ['DFCC']),
  (name: 'Nations Trust Bank', aliases: ['NTB']),
  (name: 'Pan Asia Bank', aliases: ['PABC', 'Pan Asia Banking Corporation']),
  (name: 'Union Bank of Colombo', aliases: ['Union Bank']),
  (name: 'Cargills Bank', aliases: []),
  (name: 'Amana Bank', aliases: []),
  (name: 'Sanasa Development Bank', aliases: ['SDB']),
  (name: 'HDFC Bank', aliases: ['HDFC']),
  (name: 'Regional Development Bank', aliases: ['RDB']),
  (name: 'Standard Chartered Bank', aliases: ['SCB', 'StanChart']),
  (name: 'HSBC', aliases: ['Hongkong and Shanghai']),
  (name: 'Citibank', aliases: ['Citi']),
  (name: 'State Bank of India', aliases: ['SBI']),
  (name: 'Indian Bank', aliases: []),
  (name: 'Indian Overseas Bank', aliases: ['IOB']),
  (name: 'ICICI Bank', aliases: ['ICICI']),
  (name: 'MCB Bank', aliases: ['MCB']),
  (name: 'Public Bank', aliases: []),
  (name: 'Habib Bank', aliases: ['HBL']),
  (name: 'Deutsche Bank', aliases: []),
];

List<String> get sriLankaBankNames => [
      for (final bank in kSriLankaBanks) bank.name,
    ];

/// Prefix matches first (name or alias), then contains. Empty query lists banks.
List<String> filterSriLankaBanks(String query, {int limit = 24}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return sriLankaBankNames.take(limit).toList(growable: false);
  }

  final starts = <String>[];
  final contains = <String>[];
  for (final bank in kSriLankaBanks) {
    final haystack = [
      bank.name,
      ...bank.aliases,
    ].map((value) => value.toLowerCase());
    final isPrefix = haystack.any((value) => value.startsWith(q));
    final isContains = haystack.any((value) => value.contains(q));
    if (isPrefix) {
      starts.add(bank.name);
    } else if (isContains) {
      contains.add(bank.name);
    }
  }
  return [...starts, ...contains].take(limit).toList(growable: false);
}
