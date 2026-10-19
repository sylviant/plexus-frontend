import 'package:flutter/material.dart';
import 'package:plexus/core/models/cart_item.dart';
import 'package:plexus/l10n/l10n.dart';

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  String?  _appliedPromoCode;
  double   _discountPercentage = 0.0;

  Map<String, CartItem> get items            => _items;
  int    get itemCount                       => _items.length;
  String? get appliedPromoCode              => _appliedPromoCode;
  double  get discountPercentage            => _discountPercentage;
  bool    get hasPromo                      => _appliedPromoCode != null && _discountPercentage > 0;

  double get rawPrice {
    double total = 0.0;
    _items.forEach((_, item) => total += item.price * item.quantity);
    return total;
  }

  double get discountAmount => rawPrice * (_discountPercentage / 100);
  double get totalPrice     => rawPrice - discountAmount;

  // ── Ajouter au panier avec variante optionnelle ───────────────────────────
  void add(
      Map<String, dynamic> product, {
        String? variantId,
        String? size,
        String? color,
        double? variantPrice,
        String? variantImage,
      }) {
    final String productId = (product['_id'] ?? product['id']).toString();
    final String key = variantId != null ? '${productId}_$variantId' : productId;
    final double price = variantPrice ?? (product['price'] as num).toDouble();
    final String image = variantImage ?? product['thumbnail'] ?? '';

    if (_items.containsKey(key)) {
      _items.update(
        key,
            (e) => CartItem(
          id:          productId,
          title:       e.title,
          price:       e.price,
          quantity:    e.quantity + 1,
          imageUrl:    e.imageUrl,
          productData: product,
          variantId:   variantId,
          size:        size,
          color:       color,
        ),
      );
    } else {
      _items[key] = CartItem(
        id:          productId,
        title:       product['title'] ?? l10n.produit,
        price:       price,
        quantity:    1,
        imageUrl:    image,
        productData: product,
        variantId:   variantId,
        size:        size,
        color:       color,
      );
    }
    notifyListeners();
  }

  void incrementQuantity(String key) {
    if (!_items.containsKey(key)) return;
    _items.update(key, (e) => CartItem(
      id: e.id, title: e.title, price: e.price,
      quantity: e.quantity + 1, imageUrl: e.imageUrl,
      productData: e.productData, variantId: e.variantId,
      size: e.size, color: e.color,
    ));
    notifyListeners();
  }

  void decrementQuantity(String key) {
    if (!_items.containsKey(key)) return;
    if (_items[key]!.quantity > 1) {
      _items.update(key, (e) => CartItem(
        id: e.id, title: e.title, price: e.price,
        quantity: e.quantity - 1, imageUrl: e.imageUrl,
        productData: e.productData, variantId: e.variantId,
        size: e.size, color: e.color,
      ));
    } else {
      _items.remove(key);
    }
    notifyListeners();
  }

  void applyPromo(String code, double discountPercent) {
    _appliedPromoCode   = code;
    _discountPercentage = discountPercent;
    notifyListeners();
  }

  void removePromo() {
    _appliedPromoCode   = null;
    _discountPercentage = 0.0;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _appliedPromoCode   = null;
    _discountPercentage = 0.0;
    notifyListeners();
  }
}