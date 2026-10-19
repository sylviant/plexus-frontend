import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/core/models/cart_item.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/l10n/l10n.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final TextEditingController _promoController = TextEditingController();
  bool _isVerifyingPromo = false;

  // ─── Palette ─────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);
  static const Color _green      = Color(0xFF10B981);
  static const Color _red        = Color(0xFFEF4444);

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  // ─── Vérification du code promo ───────────────────────────────────────────
  Future<void> _verifyPromo() async {
    final code = _promoController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _isVerifyingPromo = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/promo/verify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'code': code}),
      );

      final body = json.decode(response.body);

      if (response.statusCode == 200) {
        final double discount = (body['discount'] as num).toDouble();
        Provider.of<CartProvider>(context, listen: false)
            .applyPromo(code, discount);
        _showSnack(l10n.codeApplique('$code', '${discount.toStringAsFixed(0)}'),
            _green, Icons.check_circle_outline);
      } else {
        _showSnack(body['msg'] ?? l10n.codeInvalide, _red, Icons.error_outline);
      }
    } catch (e) {
      _showSnack(l10n.erreurDeConnexion, _red, Icons.wifi_off_rounded);
    } finally {
      setState(() => _isVerifyingPromo = false);
    }
  }

  void _showSnack(String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: const TextStyle(color: Colors.white))),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

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
            Text(l10n.monPanier,
                style: TextStyle(
                    color: _textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3)),
            if (cart.items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${cart.items.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
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
              padding:
              const EdgeInsets.fromLTRB(20, 16, 20, 8),
              itemCount: cart.items.length,
              itemBuilder: (context, index) {
                final item =
                cart.items.values.toList()[index];
                final key =
                cart.items.keys.toList()[index];
                return _buildCartItem(item, key, cart);
              },
            ),
          ),
          _buildCheckoutSection(context, cart),
        ],
      ),
    );
  }

  // ─── Confirm clear ────────────────────────────────────────────────────────
  void _confirmClear(BuildContext context, CartProvider cart) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.viderLePanier,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _textMain,
                fontSize: 16)),
        content: Text(
            l10n.tousLesArticlesSerontSupprimes,
            style: TextStyle(color: _textSub, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.annuler,
                  style: TextStyle(color: _textSub))),
          ElevatedButton(
            onPressed: () {
              cart.clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0),
            child: Text(l10n.vider,
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
                      offset: const Offset(0, 8))
                ],
              ),
              child: const Icon(Icons.shopping_cart_outlined,
                  size: 48, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 28),
            Text(l10n.votrePanierEstVide,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textMain)),
            const SizedBox(height: 8),
            Text(
                l10n.parcourezNotreCatalogueEtAjoutez,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: _textSub, height: 1.5)),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_primary, _primaryMid],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: _primary.withOpacity(0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32)),
                  child: Text(l10n.explorerLeCatalogue,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Cart item card ───────────────────────────────────────────────────────
  Widget _buildCartItem(CartItem item, String key, CartProvider cart) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: _primary.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // ── Image ───────────────────────────────────────────────────
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
                      borderRadius: BorderRadius.circular(13)),
                  child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: Color(0xFFCBD5E1),
                      size: 28),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // ── Infos produit ────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre
                  Text(item.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _textMain),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),

                  // ── Badge variante (si applicable) ──────────────────
                  if (item.variantLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _primary.withOpacity(0.15)),
                      ),
                      child: Text(
                        item.variantLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _primary.withOpacity(0.8),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 6),

                  // Prix
                  Text(
                    '\$${item.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.sousTotal('${(item.price * item.quantity).toStringAsFixed(2)}'),
                    style: TextStyle(
                        color: _textSub.withOpacity(0.7),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Quantité ─────────────────────────────────────────────────
            Column(
              children: [
                _QtyButton(
                    icon: Icons.add_rounded,
                    onTap: () => cart.incrementQuantity(key),
                    filled: true),
                const SizedBox(height: 6),
                Text('${item.quantity}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _textMain)),
                const SizedBox(height: 6),
                _QtyButton(
                    icon: Icons.remove_rounded,
                    onTap: () => cart.decrementQuantity(key),
                    filled: false),
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
            topRight: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: _primary.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, -6))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2)),
            ),

            // Code promo
            _buildPromoField(cart),
            const SizedBox(height: 16),

            // Summary
            _SummaryRow(
                label: l10n.articles('$totalItems'),
                value: '\$${cart.rawPrice.toStringAsFixed(2)}',
                isSubtle: true),

            if (cart.hasPromo) ...[
              const SizedBox(height: 6),
              _SummaryRow(
                label:
                l10n.reduction('${cart.appliedPromoCode}', '${cart.discountPercentage.toStringAsFixed(0)}'),
                value:
                '−\$${cart.discountAmount.toStringAsFixed(2)}',
                isSubtle: true,
                valueColor: _green,
              ),
            ],

            const SizedBox(height: 6),
            _SummaryRow(
                label: l10n.fraisEscrow0,
                value: l10n.offerts,
                isSubtle: true,
                valueColor: _green),

            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: _border)),
            _SummaryRow(
                label: l10n.totalAPayer,
                value:
                '\$${cart.totalPrice.toStringAsFixed(2)}',
                isSubtle: false),
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
                      end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: _primary.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    if (cart.items.isEmpty) return;
                    final firstItem = cart.items.values.first;
                    final sellerId =
                        firstItem.productData?['sellerId'] ??
                            l10n.inconnu;
                    context.push('/cart/payment', extra: {
                      'sellerId':      sellerId,
                      'promoCode':     cart.appliedPromoCode,
                      'promoDiscount': cart.discountPercentage,
                      'promoAmount':   cart.discountAmount,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(14))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 10),
                      Text(l10n.procederAuPaiement,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined,
                    size: 12,
                    color: _textSub.withOpacity(0.6)),
                const SizedBox(width: 5),
                Text(l10n.paiementSecuriseViaEscrowPlexus,
                    style: TextStyle(
                        fontSize: 11,
                        color: _textSub.withOpacity(0.7))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Champ code promo ─────────────────────────────────────────────────────
  Widget _buildPromoField(CartProvider cart) {
    if (cart.hasPromo) {
      return Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer_rounded,
                color: _green, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      l10n.codeApplique2('${cart.appliedPromoCode}'),
                      style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(
                      l10n.surVotreCommande('${cart.discountPercentage.toStringAsFixed(0)}'),
                      style: TextStyle(
                          color: _green.withOpacity(0.8),
                          fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                cart.removePromo();
                _promoController.clear();
              },
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                    color: _red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded,
                    color: _red, size: 16),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _promoController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
                color: _textMain,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 1.2),
            decoration: InputDecoration(
              hintText: l10n.codePromoExPlexus20,
              hintStyle: TextStyle(
                  color: _textSub.withOpacity(0.5),
                  fontSize: 13,
                  letterSpacing: 0,
                  fontWeight: FontWeight.normal),
              prefixIcon: const Icon(Icons.local_offer_outlined,
                  color: _textSub, size: 18),
              filled: true,
              fillColor: _surface,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: _border, width: 1.5)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: _border, width: 1.5)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: _primary, width: 1.8)),
            ),
            onSubmitted: (_) => _verifyPromo(),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _isVerifyingPromo ? null : _verifyPromo,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              disabledBackgroundColor: _border,
              elevation: 0,
              padding:
              const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isVerifyingPromo
                ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
                : Text(l10n.appliquer,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _QtyButton(
      {required this.icon,
        required this.onTap,
        required this.filled});

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
              : Border.all(
              color: const Color(0xFFE2E8F0), width: 1.2),
        ),
        child: Icon(icon,
            size: 15,
            color: filled
                ? Colors.white
                : const Color(0xFF64748B)),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isSubtle;
  final Color? valueColor;

  const _SummaryRow(
      {required this.label,
        required this.value,
        required this.isSubtle,
        this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                fontSize: isSubtle ? 13 : 15,
                fontWeight: isSubtle
                    ? FontWeight.w400
                    : FontWeight.w700,
                color: isSubtle
                    ? const Color(0xFF64748B)
                    : const Color(0xFF0F172A),
              )),
        ),
        Text(value,
            style: TextStyle(
              fontSize: isSubtle ? 13 : 22,
              fontWeight: isSubtle
                  ? FontWeight.w500
                  : FontWeight.w900,
              color: valueColor ??
                  (isSubtle
                      ? const Color(0xFF64748B)
                      : const Color(0xFF1A237E)),
            )),
      ],
    );
  }
}