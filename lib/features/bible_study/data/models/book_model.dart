class Book {
  const Book({
    required this.id,
    required this.name,
    required this.testament,
    required this.orderNum,
  });

  final int id;
  final String name;
  final String testament;
  final int orderNum;

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as int,
      name: json['name'] as String,
      testament: json['testament'] as String,
      orderNum: json['order_num'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'testament': testament,
      'order_num': orderNum,
    };
  }
}
