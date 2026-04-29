import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/core/providers/favorite_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({required this.productId, super.key});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<Map<String, dynamic>> _productFuture;
  final _commentController = TextEditingController();
  double _userRating = 5;

  @override
  void initState() {
    super.initState();
    _productFuture = _fetchProductDetails();
  }

  Future<Map<String, dynamic>> _fetchProductDetails() async {
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/products/${widget.productId}'));
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Produit non trouvé.');
  }

  Future<void> _submitReview() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null || _commentController.text.isEmpty) return;
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/reviews'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'productId': widget.productId,
          'userId': user.id,
          'userName': user.firstName,
          'rating': _userRating,
          'comment': _commentController.text,
        }),
      );
      _commentController.clear();
      setState(() { _productFuture = _fetchProductDetails(); });
    } catch (e) { debugPrint('Erreur avis: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF283593);
    final currentUser = Provider.of<AuthProvider>(context).currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData) return const Center(child: Text("Erreur de chargement."));

          final product = snapshot.data!;
          final String id = (product['_id'] ?? product['id']).toString(); // NORMALISATION ID
          final String title = product['title'] ?? 'Sans Titre';
          final double price = (product['price'] as num).toDouble();
          final List reviews = product['reviews'] ?? [];
          final bool isOwner = currentUser?.id == product['sellerId'];

          String lightT = ''; String boldT = title;
          if (title.contains(' ')) {
            int idx = title.indexOf(' ');
            lightT = title.substring(0, idx);
            boldT = title.substring(idx + 1);
          }

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: () => context.pop()),
                        IconButton(icon: const Icon(Icons.shopping_bag_outlined, size: 30), onPressed: () => context.go('/cart')),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lightT.isNotEmpty) Text(lightT, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w200, letterSpacing: -2)),
                        Text(boldT, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: -2, height: 0.9)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(child: Image.network(ApiConfig.getImageUrl(product['thumbnail']), height: 280, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.broken_image, size: 100))),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text("\$${price.toStringAsFixed(2)}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryBlue)),
                  ),
                  const SizedBox(height: 20),
                  if (isOwner) Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0), child: ElevatedButton.icon(onPressed: () => context.push('/profile/add-product', extra: product), icon: const Icon(Icons.edit), label: const Text("Modifier mon produit"), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white))),
                  if (!isOwner) Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      children: [
                        Expanded(child: ElevatedButton(onPressed: () { Provider.of<CartProvider>(context, listen: false).add(product); }, style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)), child: const Text("AJOUTER AU PANIER"))),
                        const SizedBox(width: 15),
                        // BOUTON FAVORIS CORRIGÉ
                        Consumer<FavoriteProvider>(
                          builder: (context, fav, child) {
                            final isFav = fav.isFavorite(id);
                            return IconButton(
                              icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: Colors.red, size: 30),
                              onPressed: () => fav.toggleFavorite(currentUser!.id, id),
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 60),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text("Détails", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  Padding(padding: const EdgeInsets.all(24), child: Text(product['description'] ?? "", style: const TextStyle(fontSize: 16, height: 1.5))),
                  const Divider(),
                  _buildReviewSection(isOwner, reviews),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewSection(bool isOwner, List reviews) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Avis clients", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          if (!isOwner) ...[
            const SizedBox(height: 10),
            Row(children: List.generate(5, (i) => IconButton(icon: Icon(i < _userRating ? Icons.star : Icons.star_border, color: Colors.orange), onPressed: () => setState(() => _userRating = i + 1.0)))),
            TextField(controller: _commentController, decoration: const InputDecoration(hintText: "Votre avis...", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _submitReview, child: const Text("Publier")),
          ],
          const SizedBox(height: 20),
          ...reviews.map((r) => ListTile(title: Text(r['userName'] ?? 'Anonyme'), subtitle: Text(r['comment']), trailing: Text("${r['rating']}⭐"))),
        ],
      ),
    );
  }
}
