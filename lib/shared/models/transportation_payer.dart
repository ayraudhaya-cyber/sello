/// Who covers transportation on an order.
enum TransportationPayer {
  seller,
  receiver;

  String get label => switch (this) {
    TransportationPayer.seller => 'Seller pays',
    TransportationPayer.receiver => 'Customer pays',
  };

  String get dbValue => name;

  static TransportationPayer fromDb(String? value) {
    return value == 'receiver'
        ? TransportationPayer.receiver
        : TransportationPayer.seller;
  }
}
