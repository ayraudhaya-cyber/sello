import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/utils/item_code_generator.dart';

void main() {
  group('parentFromName', () {
    test('keeps first word and initials of the rest', () {
      expect(ItemCodeGenerator.parentFromName('ROLEX TOWER BOLT'), 'ROLEXTB');
      expect(ItemCodeGenerator.parentFromName('Rolex Tower Bolt'), 'ROLEXTB');
    });

    test('works for any business, not just hardware', () {
      expect(ItemCodeGenerator.parentFromName('Cotton Polo Shirt'), 'COTTONPS');
      expect(ItemCodeGenerator.parentFromName('Green Tea Bags'), 'GREENTB');
    });

    test('single word is kept short and readable', () {
      expect(ItemCodeGenerator.parentFromName('Sugar'), 'SUGAR');
      expect(ItemCodeGenerator.parentFromName('Chocolates'), 'CHOCOLAT');
    });

    test('preserves useful numbers', () {
      expect(ItemCodeGenerator.parentFromName('Coca Cola 500ml'), 'COCAC500ML');
      expect(ItemCodeGenerator.parentFromName('Nail 2 Inch'), 'NAIL2I');
    });

    test('skips joiner words and punctuation', () {
      expect(
        ItemCodeGenerator.parentFromName('Salt & Pepper of the House'),
        'SALTPH',
      );
      expect(ItemCodeGenerator.parentFromName('  a-b/c  '), 'ABC');
    });

    test('is deterministic and never exceeds the max length', () {
      final name = 'Extraordinarily Long Product Name With Many Words 123456';
      final first = ItemCodeGenerator.parentFromName(name);
      expect(ItemCodeGenerator.parentFromName(name), first);
      expect(first.length, lessThanOrEqualTo(ItemCodeGenerator.maxParentLength));
      expect(RegExp(r'^[A-Z0-9]+$').hasMatch(first), isTrue);
    });

    test('returns empty when there is nothing usable', () {
      expect(ItemCodeGenerator.parentFromName(''), '');
      expect(ItemCodeGenerator.parentFromName('   '), '');
      expect(ItemCodeGenerator.parentFromName('---'), '');
    });
  });

  group('variantFromOption', () {
    test('parent code plus the distinguishing number', () {
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'ROLEXTB',
          optionLabel: '4 INCHES',
        ),
        'ROLEXTB4',
      );
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'ROLEXTB',
          optionLabel: '12 inches',
        ),
        'ROLEXTB12',
      );
    });

    test('decimals stay distinguishable', () {
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'PIPE',
          optionLabel: '2.5 inches',
        ),
        'PIPE2P5',
      );
    });

    test('sizes and colours', () {
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'POLO',
          optionLabel: 'Large',
        ),
        'POLOL',
      );
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'POLO',
          optionLabel: 'Black',
        ),
        'POLOBLA',
      );
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'POLO',
          optionLabel: 'Dark Blue',
        ),
        'POLODB',
      );
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'POLO',
          optionLabel: 'XXL',
        ),
        'POLOXXL',
      );
    });

    test('numbers with units keep the unit token', () {
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'COLA',
          optionLabel: '500ml',
        ),
        'COLA500ML',
      );
    });

    test('is empty until both parent code and option are usable', () {
      expect(
        ItemCodeGenerator.variantFromOption(parentCode: '', optionLabel: '4'),
        '',
      );
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'ROLEXTB',
          optionLabel: '  ',
        ),
        '',
      );
    });

    test('normalizes a hand-typed parent code', () {
      expect(
        ItemCodeGenerator.variantFromOption(
          parentCode: 'rolex-tb',
          optionLabel: '6',
        ),
        'ROLEXTB6',
      );
    });
  });

  group('makeUnique', () {
    test('returns the base when free', () {
      expect(ItemCodeGenerator.makeUnique('ROLEXTB', const []), 'ROLEXTB');
    });

    test('parents get a numeric variation, case-insensitively', () {
      expect(
        ItemCodeGenerator.makeUnique('ROLEXTB', const ['rolextb']),
        'ROLEXTB2',
      );
      expect(
        ItemCodeGenerator.makeUnique('ROLEXTB', const ['ROLEXTB', 'ROLEXTB2']),
        'ROLEXTB3',
      );
    });

    test('variants get a letter variation so sizes are not confused', () {
      expect(
        ItemCodeGenerator.makeUnique(
          'ROLEXTB4',
          const ['ROLEXTB4'],
          letterSuffix: true,
        ),
        'ROLEXTB4A',
      );
      expect(
        ItemCodeGenerator.makeUnique(
          'ROLEXTB4',
          const ['ROLEXTB4', 'ROLEXTB4A'],
          letterSuffix: true,
        ),
        'ROLEXTB4B',
      );
    });

    test('never grows past the maximum length', () {
      final long = 'A' * ItemCodeGenerator.maxLength;
      final result = ItemCodeGenerator.makeUnique(long, [long]);
      expect(result.length, lessThanOrEqualTo(ItemCodeGenerator.maxLength));
      expect(result, isNot(long));
    });
  });
}
