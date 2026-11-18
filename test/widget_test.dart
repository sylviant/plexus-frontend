import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/core/providers/cart_provider.dart';

// The old template test built the whole app without its providers or Firebase and could never pass.
// These tests cover the cart's money logic, which the payment screen depends on.
void main() {
  Map<String, dynamic> product(String id, num price) => {'_id': id, 'title': 'Item $id', 'price': price};

  group('CartProvider', () {
    test('adding the same product twice increases its quantity', () {
      final cart = CartProvider()..add(product('a', 10))..add(product('a', 10));
      expect(cart.itemCount, 1);
      expect(cart.items['a']!.quantity, 2);
      expect(cart.rawPrice, 20);
    });

    test('different products are separate lines and the total adds up', () {
      final cart = CartProvider()..add(product('a', 10))..add(product('b', 5.5));
      expect(cart.itemCount, 2);
      expect(cart.rawPrice, 15.5);
      expect(cart.totalPrice, 15.5);
    });

    test('a promo percentage reduces the total only', () {
      final cart = CartProvider()..add(product('a', 100))..applyPromo('SAVE10', 10);
      expect(cart.rawPrice, 100);
      expect(cart.discountAmount, 10);
      expect(cart.totalPrice, 90);
      cart.removePromo();
      expect(cart.totalPrice, 100);
    });

    test('clear empties the cart', () {
      final cart = CartProvider()..add(product('a', 10))..clear();
      expect(cart.itemCount, 0);
      expect(cart.rawPrice, 0);
    });
  });
}
