import 'package:flutter/material.dart';
import 'package:plexus/core/models/cart_item.dart';

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  // ─── Promo code state ────────────────────────────────────────────────────
  String?  _appliedPromoCode;
  double   _discountPercentage = 0.0; // % reçu du backend

  // ─── Getters ─────────────────────────────────────────────────────────────
  Map<String, CartItem> get items             => _items;
  int    get itemCount                        => _items.length;
  String? get appliedPromoCode               => _appliedPromoCode;
  double  get discountPercentage             => _discountPercentage;
  bool    get hasPromo                       => _appliedPromoCode != null && _discountPercentage > 0;

  /// Prix brut sans réduction
  double get rawPrice {
    double total = 0.0;
    _items.forEach((_, item) => total += item.price * item.quantity);
    return total;
  }

  /// Montant de la réduction en $
  double get discountAmount => rawPrice * (_discountPercentage / 100);

  /// Prix final après réduction promo
  double get totalPrice => rawPrice - discountAmount;

  // ─── Produits ─────────────────────────────────────────────────────────────
  void add(Map<String, dynamic> product) {
    final String id = (product['_id'] ?? product['id']).toString();

    if (_items.containsKey(id)) {
      _items.update(
        id,
        (existing) => CartItem(
          id:          existing.id,
          title:       existing.title,
          price:       existing.price,
          quantity:    existing.quantity + 1,
          imageUrl:    existing.imageUrl,
          productData: product,
        ),
      );
    } else {
      _items.putIfAbsent(
        id,
        () => CartItem(
          id:          id,
          title:       product['title'] ?? 'Produit',
          price:       (product['price'] as num).toDouble(),
          quantity:    1,
          imageUrl:    product['thumbnail'] ?? '',
          productData: product,
        ),
      );
    }
    notifyListeners();
  }

  void incrementQuantity(String id) {
    if (!_items.containsKey(id)) return;
    _items.update(id, (e) => CartItem(
      id: e.id, title: e.title, price: e.price,
      quantity: e.quantity + 1, imageUrl: e.imageUrl, productData: e.productData,
    ));
    notifyListeners();
  }

  void decrementQuantity(String id) {
    if (!_items.containsKey(id)) return;
    if (_items[id]!.quantity > 1) {
      _items.update(id, (e) => CartItem(
        id: e.id, title: e.title, price: e.price,
        quantity: e.quantity - 1, imageUrl: e.imageUrl, productData: e.productData,
      ));
    } else {
      _items.remove(id);
    }
    notifyListeners();
  }

  // ─── Promo code ───────────────────────────────────────────────────────────

  /// Appelé par CartScreen après vérification backend réussie
  void applyPromo(String code, double discountPercent) {
    _appliedPromoCode   = code;
    _discountPercentage = discountPercent;
    notifyListeners();
  }

  /// Retirer le code promo
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