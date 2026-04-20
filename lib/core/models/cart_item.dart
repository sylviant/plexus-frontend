class CartItem {
  final String id;
  final String title;
  final double price;
  final String imageUrl;
  int quantity;
  final Map<String, dynamic>? productData; // Ajout pour le P2P

  CartItem({
    required this.id,
    required this.title,
    required this.price,
    required this.imageUrl,
    required this.quantity,
    this.productData,
  });
}
