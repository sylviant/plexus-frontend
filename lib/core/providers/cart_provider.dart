import 'package:flutter/material.dart';
import 'package:plexus/core/models/cart_item.dart';

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => _items;

  int get itemCount => _items.length;

  double get totalPrice {
    double total = 0.0;
    _items.forEach((key, item) {
      total += item.price * item.quantity;
    });
    return total;
  }

  void add(Map<String, dynamic> product) {
    // MongoDB utilise _id, DummyJSON utilise id
    final String id = (product['_id'] ?? product['id']).toString();

    if (_items.containsKey(id)) {
      _items.update(
        id,
        (existing) => CartItem(
          id: existing.id,
          title: existing.title,
          price: existing.price,
          quantity: existing.quantity + 1,
          imageUrl: existing.imageUrl,
          productData: product, // On garde l'objet complet
        ),
      );
    } else {
      _items.putIfAbsent(
        id,
        () => CartItem(
          id: id,
          title: product['title'] ?? 'Produit',
          price: (product['price'] as num).toDouble(),
          quantity: 1,
          imageUrl: product['thumbnail'] ?? '',
          productData: product, // Stockage crucial pour le P2P
        ),
      );
    }
    notifyListeners();
  }

  void incrementQuantity(String id) {
    if (_items.containsKey(id)) {
      _items.update(id, (existing) => CartItem(
        id: existing.id,
        title: existing.title,
        price: existing.price,
        quantity: existing.quantity + 1,
        imageUrl: existing.imageUrl,
        productData: existing.productData,
      ));
      notifyListeners();
    }
  }

  void decrementQuantity(String id) {
    if (_items.containsKey(id)) {
      if (_items[id]!.quantity > 1) {
        _items.update(id, (existing) => CartItem(
          id: existing.id,
          title: existing.title,
          price: existing.price,
          quantity: existing.quantity - 1,
          imageUrl: existing.imageUrl,
          productData: existing.productData,
        ));
      } else {
        _items.remove(id);
      }
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
