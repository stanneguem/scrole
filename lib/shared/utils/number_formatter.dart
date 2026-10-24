import 'package:intl/intl.dart';

class NumberFormatter {
  NumberFormatter._();

  /// Formate un grand nombre de comptage en version compacte (ex: 1200 -> 1.2k, 1000000 -> 1M).
  static String formatCount(num value) {
    final int val = value.toInt();
    if (val >= 1000000) {
      final double millions = val / 1000000;
      return millions == millions.toInt()
          ? '${millions.toInt()}M'
          : '${millions.toStringAsFixed(1)}M';
    }
    if (val >= 1000) {
      final double thousands = val / 1000;
      return thousands == thousands.toInt()
          ? '${thousands.toInt()}k'
          : '${thousands.toStringAsFixed(1)}k';
    }
    return '$val';
  }

  /// Formate un montant monétaire exact de manière cohérente avec séparation des milliers par espace.
  /// Exemple: 10000 -> "10 000 XAF", 250000 -> "250 000 XAF", 1250.5 -> "1 250.5 EUR".
  static String formatPrice(num price, String currencyCode) {
    final bool isInteger = price == price.roundToDouble();
    final String pattern = isInteger ? '#,##0' : '#,##0.##';
    final String currency = currencyCode.trim().isEmpty ? 'XAF' : currencyCode.trim();

    final String formattedNumber = NumberFormat(pattern, 'fr_FR')
        .format(price)
        .replaceAll('\u202F', ' ')
        .replaceAll('\u00A0', ' ')
        .replaceAll(',', '.');

    return '$formattedNumber $currency';
  }

  /// Alias pour formatPrice (maintenu pour rétrocompatibilité).
  static String formatCurrency(num amount, String currencyCode, {bool compact = false}) {
    if (compact && amount >= 10000) {
      final String currency = currencyCode.trim().isEmpty ? 'XAF' : currencyCode.trim();
      return '${formatCount(amount)} $currency';
    }
    return formatPrice(amount, currencyCode);
  }
}
