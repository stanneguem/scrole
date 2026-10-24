class TicketModel {
  final String id;
  final String eventId;
  final String name;
  final double price;
  final String currency;
  final int? totalQuantity;
  final int soldQuantity;

  TicketModel({
    required this.id,
    required this.eventId,
    required this.name,
    required this.price,
    this.currency = 'XAF',
    this.totalQuantity,
    this.soldQuantity = 0,
  });

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    final idVal = (json['id'] ?? '').toString();
    final eventIdVal = (json['event_id'] ?? json['evenement_id'] ?? '').toString();
    final nameVal = (json['name'] ?? json['nom'] ?? 'Ticket').toString();
    final priceVal = toNum(json['price'] ?? json['prix']).toDouble();
    final currVal = (json['currency_code'] ?? json['currency'] ?? json['devise'] ?? 'XAF').toString();
    final totalQtyVal = json['quantity'] != null
        ? toNum(json['quantity']).toInt()
        : (json['quantite_disponible'] != null ? toNum(json['quantite_disponible']).toInt() : null);
    final soldQtyVal = toNum(json['sold_quantity'] ?? json['quantite_vendue']).toInt();

    return TicketModel(
      id: idVal,
      eventId: eventIdVal,
      name: nameVal,
      price: priceVal,
      currency: currVal,
      totalQuantity: totalQtyVal,
      soldQuantity: soldQtyVal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'name': name,
      'price': price,
      'currency_code': currency,
      if (totalQuantity != null) 'quantity': totalQuantity,
    };
  }
}
