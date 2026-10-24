import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/shared/utils/number_formatter.dart';

void main() {
  group('NumberFormatter.formatPrice', () {
    test('formats zero correctly', () {
      expect(NumberFormatter.formatPrice(0, 'XAF'), equals('0 XAF'));
    });

    test('formats single digit values', () {
      expect(NumberFormatter.formatPrice(1, 'XAF'), equals('1 XAF'));
    });

    test('formats three digit values without separator', () {
      expect(NumberFormatter.formatPrice(999, 'XAF'), equals('999 XAF'));
    });

    test('formats thousands with space separator', () {
      expect(NumberFormatter.formatPrice(1000, 'XAF'), equals('1 000 XAF'));
      expect(NumberFormatter.formatPrice(1500, 'XAF'), equals('1 500 XAF'));
    });

    test('formats tens of thousands with space separator', () {
      expect(NumberFormatter.formatPrice(10000, 'XAF'), equals('10 000 XAF'));
      expect(NumberFormatter.formatPrice(25000, 'XAF'), equals('25 000 XAF'));
    });

    test('formats hundreds of thousands with space separator', () {
      expect(NumberFormatter.formatPrice(100000, 'XAF'), equals('100 000 XAF'));
      expect(NumberFormatter.formatPrice(250000, 'XAF'), equals('250 000 XAF'));
    });

    test('formats millions with space separator', () {
      expect(NumberFormatter.formatPrice(1000000, 'XAF'), equals('1 000 000 XAF'));
    });

    test('supports different currency codes dynamically', () {
      expect(NumberFormatter.formatPrice(10000, 'EUR'), equals('10 000 EUR'));
      expect(NumberFormatter.formatPrice(10000, 'USD'), equals('10 000 USD'));
      expect(NumberFormatter.formatPrice(10000, 'FCFA'), equals('10 000 FCFA'));
    });

    test('handles decimal values without loss of precision', () {
      expect(NumberFormatter.formatPrice(1250.5, 'EUR'), equals('1 250.5 EUR'));
    });
  });

  group('NumberFormatter.formatCount', () {
    test('formats counts compactly', () {
      expect(NumberFormatter.formatCount(500), equals('500'));
      expect(NumberFormatter.formatCount(1200), equals('1.2k'));
      expect(NumberFormatter.formatCount(10000), equals('10k'));
      expect(NumberFormatter.formatCount(1000000), equals('1M'));
    });
  });
}
