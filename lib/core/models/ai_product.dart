class AiProduct {
  final String productId;
  final String name;
  final double price;
  final String color;
  final String imageUrl;
  final String relevance;

  AiProduct({
    required this.productId,
    required this.name,
    required this.price,
    required this.color,
    required this.imageUrl,
    required this.relevance,
  });

  factory AiProduct.fromJson(Map<String, dynamic> json) {
    return AiProduct(
      productId: json['product_id'] ?? '',
      name: json['name'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      color: json['color'] ?? '',
      imageUrl: json['image_url'] ?? '',
      relevance: json['relevance'] ?? '',
    );
  }
}