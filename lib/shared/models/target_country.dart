class TargetCountry {
  final String displayName;
  final String packageName;

  const TargetCountry({required this.displayName, required this.packageName});

  factory TargetCountry.fromMap(Map<String, dynamic> map) {
    return TargetCountry(
      displayName: (map['displayName'] ?? '') as String,
      packageName: (map['packageName'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'packageName': packageName,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TargetCountry &&
              runtimeType == other.runtimeType &&
              packageName == other.packageName;

  @override
  int get hashCode => packageName.hashCode;

  @override
  String toString() => 'TargetCountry($displayName -> $packageName)';
}