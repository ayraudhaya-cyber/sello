import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/data/sri_lanka_banks.dart';

void main() {
  test('lists major Sri Lankan banks', () {
    expect(sriLankaBankNames, contains('Bank of Ceylon'));
    expect(sriLankaBankNames, contains('Hatton National Bank'));
    expect(sriLankaBankNames, contains("People's Bank"));
  });

  test('empty query shows banks as a dropdown list', () {
    final results = filterSriLankaBanks('');
    expect(results, isNotEmpty);
    expect(results.first, 'Bank of Ceylon');
  });

  test('aliases match the official bank name', () {
    expect(filterSriLankaBanks('hnb'), ['Hatton National Bank']);
    expect(filterSriLankaBanks('boc'), contains('Bank of Ceylon'));
    expect(filterSriLankaBanks('ntb'), ['Nations Trust Bank']);
  });

  test('prefix matches rank above later contains matches', () {
    final results = filterSriLankaBanks('bank');
    expect(results.first, 'Bank of Ceylon');
  });

  test('unknown names are not forced onto the list', () {
    expect(filterSriLankaBanks('Village Co-op Bank'), isEmpty);
  });
}
