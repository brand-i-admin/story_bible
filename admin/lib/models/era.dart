class Era {
  const Era({required this.id, required this.code, required this.name});

  factory Era.fromMap(Map<String, dynamic> row) {
    return Era(
      id: row['id'] as String,
      code: row['code'] as String,
      name: row['name'] as String,
    );
  }

  final String id;
  final String code;
  final String name;
}
