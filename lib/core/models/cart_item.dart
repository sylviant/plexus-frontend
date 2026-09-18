class CartItem {
  final String id;
  final String title;
  final double price;
  final String imageUrl;
  int quantity;
  final Map<String, dynamic>? productData;

  // ── Variante ──────────────────────────────────────────────────────────────
  final String? variantId;
  final String? size;
  final String? color;

  CartItem({
    required this.id,
    required this.title,
    required this.price,
    required this.imageUrl,
    required this.quantity,
    this.productData,
    this.variantId,
    this.size,
    this.color,
  });

  /// Clé unique : productId + variantId (si variante)
  String get cartKey => variantId != null ? '${id}_$variantId' : id;

  /// Label affiché dans le panier
  String get variantLabel {
    if (size != null && color != null) return '$size / $color';
    if (size != null) return size!;
    if (color != null) return color!;
    return '';
  }
}