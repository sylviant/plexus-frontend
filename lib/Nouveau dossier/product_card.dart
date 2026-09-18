import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;

  const ProductCard({required this.product, super.key});

  // ─── Palette ──────────────────────────────────────────────────────────────
  static const Color _navy = Color(0xFF0D1B4B);
  static const Color _textSub = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final String productId =
        (product['_id'] ?? product['id'] ?? '').toString();
    final String title = product['title'] ?? 'Sans titre';
    final double price = (product['price'] as num?)?.toDouble() ?? 0.0;

    final String imageUrl =
        ApiConfig.getImageUrl(product['thumbnail'] ?? product['image']);

    return GestureDetector(
      onTap: () => context.push('/home/product/$productId'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEBEFF8), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image (carrée, style Alibaba) ─────────────────────────────
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(9)),
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
            ),

            // ── Infos produit ────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "\$${price.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}