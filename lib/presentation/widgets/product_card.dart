import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;

  const ProductCard({required this.product, super.key});

  @override
  Widget build(BuildContext context) {
    final String productId = (product['_id'] ?? product['id'] ?? '').toString();
    final String title = product['title'] ?? 'Sans titre';
    final double price = (product['price'] as num?)?.toDouble() ?? 0.0;

    // UTILISATION DE LA FONCTION UNIFIÉE
    final String imageUrl = ApiConfig.getImageUrl(product['thumbnail'] ?? product['image']);

    return GestureDetector(
      onTap: () => context.push('/home/product/$productId'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey[100],
                    child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 30),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("\$${price.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF283593), fontWeight: FontWeight.w900, fontSize: 15)),
                      GestureDetector(
                        onTap: () {
                          Provider.of<CartProvider>(context, listen: false).add(product);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$title ajouté"), duration: const Duration(seconds: 1)));
                        },
                        child: const CircleAvatar(radius: 14, backgroundColor: Color(0xFF283593), child: Icon(Icons.add, color: Colors.white, size: 16)),
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
