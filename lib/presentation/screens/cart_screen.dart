import 'package:flutter/material.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/core/models/cart_item.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  // ─── Palette ─────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: _primary.withOpacity(0.08),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Mon Panier',
              style: TextStyle(
                color: _textMain,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            if (cart.items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${cart.items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        centerTitle: true,
        actions: [
          if (cart.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFECACA), width: 1.2),
                  ),
                  child: const Icon(Icons.delete_sweep_outlined,
                      color: Color(0xFFEF4444), size: 18),
                ),
                onPressed: () => _confirmClear(context, cart),
              ),
            ),
        ],
      ),
      body: cart.items.isEmpty
          ? _buildEmptyCart(context)
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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

  // ─── Confirm clear dialog ─────────────────────────────────────────────────

  void _confirmClear(BuildContext context, CartProvider cart) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Vider le panier',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _textMain,
                fontSize: 16)),
        content: const Text(
            'Tous les articles seront supprimés. Confirmer ?',
            style: TextStyle(color: _textSub, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler',
                style: TextStyle(color: _textSub)),
          ),
          ElevatedButton(
            onPressed: () {
              cart.clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Vider',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _primary.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.shopping_cart_outlined,
                  size: 48, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 28),
            const Text(
              'Votre panier est vide',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textMain),
            ),
            const SizedBox(height: 8),
            const Text(
              'Parcourez notre catalogue et ajoutez vos articles préférés.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSub, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primary, _primaryMid],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withOpacity(0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 32),
                  ),
                  child: const Text(
                    'EXPLORER LE CATALOGUE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Cart item card ───────────────────────────────────────────────────────

  Widget _buildCartItem(CartItem item, String id, CartProvider cart) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.network(
                ApiConfig.getImageUrl(item.imageUrl),
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: Color(0xFFCBD5E1), size: 28),
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _textMain,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\$${item.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sous-total : \$${(item.price * item.quantity).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: _textSub.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Quantity control
            Column(
              children: [
                _QtyButton(
                  icon: Icons.add_rounded,
                  onTap: () => cart.incrementQuantity(id),
                  filled: true,
                ),
                const SizedBox(height: 6),
                Text(
                  '${item.quantity}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _textMain,
                  ),
                ),
                const SizedBox(height: 6),
                _QtyButton(
                  icon: Icons.remove_rounded,
                  onTap: () => cart.decrementQuantity(id),
                  filled: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Checkout section ─────────────────────────────────────────────────────

  Widget _buildCheckoutSection(BuildContext context, CartProvider cart) {
    final int totalItems =
        cart.items.values.fold(0, (sum, i) => sum + i.quantity);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Summary rows
            _SummaryRow(
              label: 'Articles ($totalItems)',
              value: '\$${cart.totalPrice.toStringAsFixed(2)}',
              isSubtle: true,
            ),
            const SizedBox(height: 6),
            _SummaryRow(
              label: 'Frais Escrow (0%)',
              value: 'Offerts',
              isSubtle: true,
              valueColor: const Color(0xFF10B981),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: _border),
            ),

            _SummaryRow(
              label: 'Total à payer',
              value: '\$${cart.totalPrice.toStringAsFixed(2)}',
              isSubtle: false,
            ),

            const SizedBox(height: 20),

            // Checkout button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primary, _primaryMid],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    if (cart.items.isEmpty) return;
                    final firstItem = cart.items.values.first;
                    final sellerId =
                        firstItem.productData?['sellerId'] ?? 'Inconnu';
                    context.push('/cart/payment',
                        extra: {'sellerId': sellerId});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.lock_outline_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 10),
                      Text(
                        'PROCÉDER AU PAIEMENT',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Security badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined,
                    size: 12, color: _textSub.withOpacity(0.6)),
                const SizedBox(width: 5),
                Text(
                  'Paiement sécurisé via Escrow PLEXUS',
                  style: TextStyle(
                      fontSize: 11, color: _textSub.withOpacity(0.7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _QtyButton({
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: filled
              ? const Color(0xFF1A237E)
              : const Color(0xFFF4F6FB),
          borderRadius: BorderRadius.circular(8),
          border: filled
              ? null
              : Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        ),
        child: Icon(
          icon,
          size: 15,
          color: filled ? Colors.white : const Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isSubtle;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.isSubtle,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isSubtle ? 13 : 15,
            fontWeight:
                isSubtle ? FontWeight.w400 : FontWeight.w700,
            color: isSubtle
                ? const Color(0xFF64748B)
                : const Color(0xFF0F172A),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isSubtle ? 13 : 22,
            fontWeight:
                isSubtle ? FontWeight.w500 : FontWeight.w900,
            color: valueColor ??
                (isSubtle
                    ? const Color(0xFF64748B)
                    : const Color(0xFF1A237E)),
          ),
        ),
      ],
    );
  }
}