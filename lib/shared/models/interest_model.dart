class Interest {
  final String id;
  final String name;
  final String? category;
  final String? iconUrl;
  final bool isSelected;

  Interest({
    required this.id,
    required this.name,
    this.category,
    this.iconUrl,
    this.isSelected = false,
  });

  factory Interest.fromJson(Map<String, dynamic> json) {
    return Interest(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString(),
      iconUrl: json['icon_url']?.toString(),
      isSelected: json['is_selected'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'icon_url': iconUrl,
      'is_selected': isSelected,
    };
  }

  Interest copyWith({
    String? id,
    String? name,
    String? category,
    String? iconUrl,
    bool? isSelected,
  }) {
    return Interest(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      iconUrl: iconUrl ?? this.iconUrl,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}