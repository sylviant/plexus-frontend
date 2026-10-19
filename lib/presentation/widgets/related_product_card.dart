import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/l10n/l10n.dart';

class RelatedProductCard extends StatelessWidget {
  final Map<String, dynamic> product;

  const RelatedProductCard({required this.product, super.key});

  // ─── Palette (cohérente avec le thème de l'app) ───────────────────────────
  static const Color _primary = Color(0xFF1A237E);
  static const Color _gold    = Color(0xFFFBC02D);
  static const Color _textSub = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final String productId =
        (product['_id'] ?? product['id'] ?? '').toString();
    final String title = product['title'] ?? l10n.sansTitre;
    final double price = (product['price'] as num?)?.toDouble() ?? 0.0;
    final String imageUrl =
        ApiConfig.getImageUrl(product['thumbnail'] ?? product['image']);

    return GestureDetector(
      onTap: () => context.push('/home/product/$productId'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEBEFF8), width: 1),
          boxShadow: [
            BoxShadow(
              color: _primary.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image (hauteur libre → effet Masonry) ────────────────────
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 120,
                  color: const Color(0xFFF0F3FF),
                  child: const Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        color: Color(0xFF8A94B2), size: 24),
                  ),
                ),
              ),
            ),

            // ── Infos + actions rapides ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "\$${price.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: _textSub,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Icônes d'action rapide (Panier / Achat direct) ────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Ajout rapide au panier
                      GestureDetector(
                        onTap: () {
                          Provider.of<CartProvider>(context, listen: false)
                              .add(product);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.ajouteAuPanier2('$title')),
                              backgroundColor: const Color(0xFF00B386),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.shopping_cart_outlined,
                              size: 15, color: _primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Achat direct → paiement
                      GestureDetector(
                        onTap: () => context.push('/cart/payment', extra: {
                          'singleProduct': product,
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              size: 15, color: _primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}