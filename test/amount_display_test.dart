import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/utils/formatters.dart';

void main() {
  const symbol = 'Rs ';
  const amount = 8350073.93;

  test('exact summary matches the full currency figure', () {
    expect(
      SelloFormatters.summaryAmount(
        amount,
        symbol: symbol,
        style: AmountDisplayStyle.exact,
      ),
      SelloFormatters.currency(amount, symbol: symbol),
    );
    expect(
      SelloFormatters.currency(amount, symbol: symbol),
      'Rs 8,350,073.93',
    );
  });

  test('lakhs and millions shorten only large summary amounts', () {
    expect(
      SelloFormatters.summaryAmount(
        amount,
        symbol: symbol,
        style: AmountDisplayStyle.lakhs,
      ),
      'Rs 83.5 lakhs',
    );
    expect(
      SelloFormatters.summaryAmount(
        amount,
        symbol: symbol,
        style: AmountDisplayStyle.millions,
      ),
      'Rs 8.35m',
    );
    expect(
      SelloFormatters.summaryAmount(
        100000,
        symbol: symbol,
        style: AmountDisplayStyle.lakhs,
      ),
      'Rs 1 lakh',
    );
    expect(
      SelloFormatters.summaryAmount(
        50000,
        symbol: symbol,
        style: AmountDisplayStyle.lakhs,
      ),
      'Rs 50,000.00',
    );
    expect(
      SelloFormatters.summaryAmount(
        175526,
        symbol: symbol,
        style: AmountDisplayStyle.millions,
      ),
      'Rs 175,526.00',
    );
  });

  test('LKR uses the rupee symbol, not a dollar sign', () {
    expect(SelloFormatters.currencySymbol('LKR'), 'Rs ');
    expect(SelloFormatters.currencySymbol('lkr'), 'Rs ');
    expect(
      SelloFormatters.currency(242004, symbol: SelloFormatters.currencySymbol('LKR')),
      isNot(contains('\$')),
    );
  });
}
