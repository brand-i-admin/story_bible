class VersePage {
  const VersePage({
    required this.orderNum,
    required this.ref,
    required this.text,
  });

  final int orderNum;
  final String ref;
  final String text;

  factory VersePage.fromJson(Map<String, dynamic> json) {
    return VersePage(
      orderNum: json['order_num'] as int,
      ref: json['ref'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'order_num': orderNum, 'ref': ref, 'text': text};
  }
}
