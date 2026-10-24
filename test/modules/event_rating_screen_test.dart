import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/shared/utils/number_formatter.dart';

void main() {
  group('NumberFormatter Global Usage Tests', () {
    test('formatCount formats small, thousands and millions correctly', () {
      expect(NumberFormatter.formatCount(0), equals('0'));
      expect(NumberFormatter.formatCount(999), equals('999'));
      expect(NumberFormatter.formatCount(1000), equals('1k'));
      expect(NumberFormatter.formatCount(1245), equals('1.2k'));
      expect(NumberFormatter.formatCount(10000), equals('10k'));
      expect(NumberFormatter.formatCount(1000000), equals('1M'));
    });

    test('formatPrice formats free and paid amounts with currency symbol', () {
      expect(NumberFormatter.formatPrice(0, 'XAF'), contains('0 XAF'));
      expect(NumberFormatter.formatPrice(5000, 'FCFA'), contains('5 000 FCFA'));
    });
  });
}
