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

  // ─── Palette ────────────────────────────────────────────────────────────────
  static const Color _bg         = Color(0xFF0F1117);
  static const Color _surface    = Color(0xFF1A1D27);
  static const Color _surfaceAlt = Color(0xFF21253A);
  static const Color _accent     = Color(0xFF4F6EF7);
  static const Color _textPri    = Color(0xFFEBEDF5);
  static const Color _textSec    = Color(0xFF7B8097);
  static const Color _divider    = Color(0xFF252838);
  static const Color _green      = Color(0xFF34C97B);
  static const Color _orange     = Color(0xFFF5A623);

  @override
  void initState() {
    super.initState();
    _productFuture = _fetchProductDetails();
  }

  Future<Map<String, dynamic>> _fetchProductDetails() async {
    final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/products/${widget.productId}'));
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
    final currentUser = Provider.of<AuthProvider>(context).currentUser;

    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _accent, strokeWidth: 2));
          }
          if (!snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: _textSec, size: 48),
                  const SizedBox(height: 16),
                  const Text("Erreur de chargement.",
                      style: TextStyle(color: _textSec, fontSize: 16)),
                ],
              ),
            );
          }

          final product = snapshot.data!;
          final String id = (product['_id'] ?? product['id']).toString(); // NORMALISATION ID
          final String title = product['title'] ?? 'Sans Titre';
          final double price = (product['price'] as num).toDouble();
          final List reviews = product['reviews'] ?? [];
          final bool isOwner = currentUser?.id == product['sellerId'];

          String lightT = '';
          String boldT = title;
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
                  // ── Top Nav ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _navButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => context.pop(),
                        ),
                        _navButton(
                          icon: Icons.shopping_bag_outlined,
                          onTap: () => context.go('/cart'),
                        ),
                      ],
                    ),
                  ),

                  // ── Title ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lightT.isNotEmpty)
                          Text(lightT,
                              style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w200,
                                  letterSpacing: -1.5,
                                  color: _textSec)),
                        Text(boldT,
                            style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5,
                                height: 0.95,
                                color: _textPri)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Product Image ──────────────────────────────────────
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      height: 260,
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _divider),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        ApiConfig.getImageUrl(product['thumbnail']),
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => const Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 60, color: _textSec),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Price & Actions ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Prix",
                                style: TextStyle(
                                    color: _textSec,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1)),
                            const SizedBox(height: 2),
                            Text("\$${price.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: _accent,
                                  letterSpacing: -1,
                                )),
                          ],
                        ),
                        if (isOwner)
                          ElevatedButton.icon(
                            onPressed: () => context.push(
                                '/profile/add-product',
                                extra: product),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text("Modifier",
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Cart + Favorite ────────────────────────────────────
                  if (!isOwner)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Provider.of<CartProvider>(context,
                                          listen: false)
                                      .add(product);
                                },
                                icon: const Icon(
                                    Icons.shopping_cart_outlined,
                                    size: 18),
                                label: const Text("Ajouter au panier",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // BOUTON FAVORIS CORRIGÉ
                          Consumer<FavoriteProvider>(
                            builder: (context, fav, child) {
                              final isFav = fav.isFavorite(id);
                              return GestureDetector(
                                onTap: () =>
                                    fav.toggleFavorite(currentUser!.id, id),
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: isFav
                                        ? const Color(0xFFEF5350)
                                            .withOpacity(0.15)
                                        : _surface,
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isFav
                                          ? const Color(0xFFEF5350)
                                              .withOpacity(0.4)
                                          : _divider,
                                    ),
                                  ),
                                  child: Icon(
                                    isFav
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: isFav
                                        ? const Color(0xFFEF5350)
                                        : _textSec,
                                    size: 22,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 36),

                  // ── Description Section ────────────────────────────────
                  _buildSectionDivider("Détails"),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Text(
                      product['description'] ?? "",
                      style: const TextStyle(
                          fontSize: 15,
                          height: 1.7,
                          color: _textSec),
                    ),
                  ),

                  // ── Reviews Section ────────────────────────────────────
                  _buildSectionDivider("Avis clients"),
                  _buildReviewSection(isOwner, reviews),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Nav Button ──────────────────────────────────────────────────────────────
  Widget _navButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _divider),
        ),
        child: Icon(icon, size: 18, color: _textPri),
      ),
    );
  }

  // ─── Section Divider ─────────────────────────────────────────────────────────
  Widget _buildSectionDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
                color: _textSec,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: _divider)),
        ],
      ),
    );
  }

  // ─── Review Section ───────────────────────────────────────────────────────────
  Widget _buildReviewSection(bool isOwner, List reviews) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Star Input ──────────────────────────────────────────────
          if (!isOwner) ...[
            const SizedBox(height: 16),
            const Text("Votre évaluation",
                style: TextStyle(
                    color: _textSec,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            Row(
              children: List.generate(
                5,
                (i) => GestureDetector(
                  onTap: () => setState(() => _userRating = i + 1.0),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      i < _userRating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: _orange,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _commentController,
              maxLines: 3,
              style: const TextStyle(color: _textPri, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Partagez votre expérience avec ce produit...",
                hintStyle: const TextStyle(color: Color(0xFF3D4155), fontSize: 13),
                filled: true,
                fillColor: _surfaceAlt,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _divider)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _divider)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: _accent, width: 1.5)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Publier l'avis",
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // ── Reviews List ────────────────────────────────────────────
          if (reviews.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _divider),
              ),
              child: const Center(
                child: Text("Aucun avis pour ce produit.",
                    style: TextStyle(color: _textSec, fontSize: 14)),
              ),
            )
          else
            ...reviews.map((r) => _buildReviewCard(r)),
        ],
      ),
    );
  }

  Widget _buildReviewCard(dynamic r) {
    final double rating = (r['rating'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (r['userName'] ?? 'A')[0].toUpperCase(),
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(r['userName'] ?? 'Anonyme',
                      style: const TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ],
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i < rating ? _orange : _divider,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(r['comment'] ?? '',
              style: const TextStyle(
                  color: _textSec, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}