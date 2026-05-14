import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';

class ProductCard extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductCard({required this.product, super.key});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  // ─── Palette ──────────────────────────────────────────────────────────────
  static const Color _navy = Color(0xFF0D1B4B);
  static const Color _accent = Color(0xFF4A6CF7);

  late AnimationController _addController;
  late Animation<double> _scaleAnim;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    _addController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(parent: _addController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  // ─── BACKEND (inchangé) ──────────────────────────────────────────────────
  void _handleAddToCart(BuildContext context, String title) async {
    await _addController.forward();
    await _addController.reverse();

    Provider.of<CartProvider>(context, listen: false).add(widget.product);
    setState(() => _added = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text("$title ajouté au panier"),
          ],
        ),
        backgroundColor: const Color(0xFF00B386),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _added = false);
  }

  @override
  Widget build(BuildContext context) {
    final String productId =
        (widget.product['_id'] ?? widget.product['id'] ?? '').toString();
    final String title = widget.product['title'] ?? 'Sans titre';
    final double price =
        (widget.product['price'] as num?)?.toDouble() ?? 0.0;

    // UTILISATION DE LA FONCTION UNIFIÉE
    final String imageUrl = ApiConfig.getImageUrl(
        widget.product['thumbnail'] ?? widget.product['image']);

    return GestureDetector(
      onTap: () => context.push('/home/product/$productId'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEBEFF8), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A6CF7).withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ──────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(19)),
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFFF0F3FF),
                        child: const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: Color(0xFF8A94B2),
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Badge prix flottant
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        "\$${price.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Infos produit ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _navy,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Bouton Ajouter ─────────────────────────────────────
                  GestureDetector(
                    onTap: () => _handleAddToCart(context, title),
                    child: AnimatedBuilder(
                      animation: _scaleAnim,
                      builder: (context, child) => Transform.scale(
                        scale: _scaleAnim.value,
                        child: child,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: double.infinity,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _added ? const Color(0xFF00B386) : _accent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: (_added
                                      ? const Color(0xFF00B386)
                                      : _accent)
                                  .withOpacity(0.28),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _added
                                ? const Row(
                                    key: ValueKey('check'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_rounded,
                                          color: Colors.white, size: 14),
                                      SizedBox(width: 5),
                                      Text(
                                        "Ajouté",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Row(
                                    key: ValueKey('add'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_rounded,
                                          color: Colors.white, size: 14),
                                      SizedBox(width: 5),
                                      Text(
                                        "Ajouter",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
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