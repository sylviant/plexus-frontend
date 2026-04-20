import 'package:flutter/material.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/core/models/cart_item.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('MON PANIER', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18)),
        centerTitle: true,
        actions: [
          if (cart.items.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent), onPressed: () => cart.clear()),
        ],
      ),
      body: cart.items.isEmpty
          ? _buildEmptyCart(context)
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items.values.toList()[index];
                      final productId = cart.items.keys.toList()[index];
                      return _buildCartItem(item, productId, cart);
                    },
                  ),
                ),
                _buildCheckoutSection(context, cart),
              ],
            ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)]),
            child: Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey[300]),
          ),
          const SizedBox(height: 30),
          const Text("Votre panier est vide", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => context.go('/home'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40)),
            child: const Text("FAIRE MON SHOPPING"),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item, String id, CartProvider cart) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.network(
              ApiConfig.getImageUrl(item.imageUrl),
              width: 80, height: 80, fit: BoxFit.cover,
              errorBuilder: (c,e,s) => Container(width: 80, height: 80, color: Colors.grey[100], child: const Icon(Icons.image_not_supported_outlined)),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text("\$${item.price.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Row(
            children: [
              _buildQtyBtn(Icons.remove, () => cart.decrementQuantity(id)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text("${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              _buildQtyBtn(Icons.add, () => cart.incrementQuantity(id)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: Colors.black87),
      ),
    );
  }

  Widget _buildCheckoutSection(BuildContext context, CartProvider cart) {
    const Color primaryColor = Color(0xFF1A237E);
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total à payer", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
                Text("\$${cart.totalPrice.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: primaryColor)),
              ],
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    if (cart.items.isEmpty) return;
                    final firstItem = cart.items.values.first;
                    // Utilisation de l'opérateur null-aware pour corriger l'erreur
                    final sellerId = firstItem.productData?['sellerId'] ?? 'Inconnu';
                    context.push('/cart/payment', extra: {'sellerId': sellerId});
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
                  child: const Text("PROCÉDER AU PAIEMENT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
