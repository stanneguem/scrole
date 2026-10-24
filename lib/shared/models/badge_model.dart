class BadgeModel {
  final String id;
  final String name;
  final String? description;
  final String? iconUrl;

  BadgeModel({
    required this.id,
    required this.name,
    this.description,
    this.iconUrl,
  });
}