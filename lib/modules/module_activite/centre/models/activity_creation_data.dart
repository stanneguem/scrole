class ActivityCreationData {
  final String title;
  final String description;
  final double priceGeneral;
  final String currencyCode;
  final List<String> interestIds;

  ActivityCreationData({
    required this.title,
    required this.description,
    required this.priceGeneral,
    this.currencyCode = 'XAF',
    required this.interestIds,
  });

  Map<String, dynamic> toJson() {
    return {
      'p_title': title.trim(),
      'p_description': description.trim(),
      'p_price_general': priceGeneral,
      'currency_code': currencyCode,
      'p_interest_ids': interestIds,
    };
  }
}
