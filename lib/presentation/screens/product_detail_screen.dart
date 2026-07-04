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

  // Carrousel images
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  // ─── Palette (light - style "After") ──────────────────────────────────────
  static const Color _bg        = Color(0xFFFFFFFF);
  static const Color _surface   = Color(0xFFF7F8FA);
  static const Color _border    = Color(0xFFEEEFF2);
  static const Color _primary   = Color(0xFF1A237E);
  static const Color _accent    = Color(0xFF2563EB);
  static const Color _green     = Color(0xFF16A34A);
  static const Color _orange    = Color(0xFFF59E0B);
  static const Color _red       = Color(0xFFEF4444);
  static const Color _textMain  = Color(0xFF0F172A);
  static const Color _textSub   = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _productFuture = _fetchProductDetails();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ─── Backend logic (unchanged) ────────────────────────────────────────────

  Future<Map<String, dynamic>> _fetchProductDetails() async {
    final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/products/${widget.productId}'));
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Produit non trouve.');
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
      setState(() => _productFuture = _fetchProductDetails());
    } catch (e) {
      debugPrint('Erreur avis: $e');
    }
  }

  // ─── Helper : construit la liste de toutes les images du produit ──────────
  // Backend stocke :
  //   product['thumbnail']  → 1 image principale (ancienne route .single)
  //   product['images']     → tableau d'images (nouvelle route .fields)
  //   product['video']      → URL vidéo (optionnel)
  List<String> _getImages(Map<String, dynamic> product) {
    final List<String> urls = [];

    // Nouvelles images (tableau)
    final dynamic imgs = product['images'];
    if (imgs != null && imgs is List) {
      for (final img in imgs) {
        final String url = ApiConfig.getImageUrl(img.toString());
        if (url.isNotEmpty) urls.add(url);
      }
    }

    // Fallback : thumbnail (ancienne structure)
    if (urls.isEmpty && product['thumbnail'] != null) {
      final String t = ApiConfig.getImageUrl(product['thumbnail'].toString());
      if (t.isNotEmpty) urls.add(t);
    }

    return urls;
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

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
          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.error_outline, color: _textSub, size: 48),
                SizedBox(height: 16),
                Text("Erreur de chargement.",
                    style: TextStyle(color: _textSub, fontSize: 16)),
              ]),
            );
          }

          final product   = snapshot.data!;
          final String id = (product['_id'] ?? product['id']).toString();
          final String title    = product['title'] ?? 'Sans Titre';
          final double price    = (product['price'] as num).toDouble();
          final double oldPrice = (product['oldPrice'] as num? ?? 0).toDouble();
          final String desc     = product['description'] ?? '';
          final List reviews    = product['reviews'] ?? [];
          final String? videoUrl = product['video'] != null
              ? ApiConfig.getImageUrl(product['video'].toString())
              : null;
          final bool isOwner    = currentUser?.id == product['sellerId'];
          final List<String> images = _getImages(product);

          // Calcul réduction
          final bool hasDiscount = oldPrice > price && oldPrice > 0;
          final int discountPct = hasDiscount
              ? (((oldPrice - price) / oldPrice) * 100).round()
              : 0;

          // Note moyenne
          double avgRating = 0;
          if (reviews.isNotEmpty) {
            double sum = 0;
            for (final r in reviews) {
              sum += (r['rating'] as num?)?.toDouble() ?? 0;
            }
            avgRating = sum / reviews.length;
          }

          return CustomScrollView(
            slivers: [
              // ── SliverAppBar avec carrousel images ────────────────────
              SliverAppBar(
                expandedHeight: 340,
                pinned: true,
                backgroundColor: _bg,
                elevation: 0,
                scrolledUnderElevation: 1,
                shadowColor: _primary.withOpacity(0.08),
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 8)
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 17, color: _textMain),
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: GestureDetector(
                      onTap: () => context.go('/cart'),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 8)
                          ],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.shopping_bag_outlined,
                              size: 20, color: _textMain),
                        ),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    children: [
                      // Carrousel d'images
                      images.isEmpty
                          ? Container(
                              color: _surface,
                              child: const Center(
                                child: Icon(Icons.image_outlined,
                                    size: 80, color: _textMuted),
                              ),
                            )
                          : PageView.builder(
                              controller: _pageController,
                              itemCount: images.length,
                              onPageChanged: (i) =>
                                  setState(() => _currentImageIndex = i),
                              itemBuilder: (context, i) => Container(
                                color: _surface,
                                child: Image.network(
                                  images[i],
                                  fit: BoxFit.contain,
                                  errorBuilder: (c, e, s) => const Center(
                                    child: Icon(Icons.broken_image_outlined,
                                        size: 60, color: _textMuted),
                                  ),
                                ),
                              ),
                            ),

                      // Badge SAVE % (en haut à droite de l'image)
                      if (hasDiscount)
                        Positioned(
                          top: 60,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'SAVE $discountPct%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),

                      // Dots indicateur
                      if (images.length > 1)
                        Positioned(
                          bottom: 14,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (i) {
                              final bool active = _currentImageIndex == i;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: active ? 20 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: active ? _accent : _textMuted.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Contenu produit ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: _bg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── En-tête : titre, note, marque ────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Catégorie badge
                            if (product['category'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _accent.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (product['category'] as String).toUpperCase(),
                                  style: TextStyle(
                                    color: _accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),

                            const SizedBox(height: 8),

                            // Titre
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _textMain,
                                height: 1.2,
                                letterSpacing: -0.3,
                              ),
                            ),

                            const SizedBox(height: 6),

                            // Sous-titre description courte
                            if (desc.isNotEmpty)
                              Text(
                                desc.length > 80
                                    ? '${desc.substring(0, 80)}...'
                                    : desc,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: _textSub,
                                    height: 1.4),
                              ),

                            const SizedBox(height: 12),

                            // Étoiles + nb avis
                            Row(children: [
                              ...List.generate(5, (i) => Icon(
                                i < avgRating.floor()
                                    ? Icons.star_rounded
                                    : (i < avgRating
                                        ? Icons.star_half_rounded
                                        : Icons.star_outline_rounded),
                                color: _orange,
                                size: 16,
                              )),
                              const SizedBox(width: 6),
                              Text(
                                avgRating > 0
                                    ? '${avgRating.toStringAsFixed(1)} (${reviews.length} avis)'
                                    : 'Aucun avis',
                                style: const TextStyle(
                                    color: _textSub, fontSize: 12),
                              ),
                            ]),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      _Divider(),

                      // ── Prix ─────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: _textMain,
                                letterSpacing: -1,
                              ),
                            ),
                            if (hasDiscount) ...[
                              const SizedBox(width: 10),
                              Text(
                                '\$${oldPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _textMuted,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                            const Spacer(),
                            // Bouton modifier (owner only)
                            if (isOwner)
                              GestureDetector(
                                onTap: () => context.push(
                                    '/profile/add-product',
                                    extra: product),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _orange.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: _orange.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.edit_outlined,
                                          size: 14, color: _orange),
                                      SizedBox(width: 5),
                                      Text('Modifier',
                                          style: TextStyle(
                                              color: _orange,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Feature badges (style "After") ────────────────
                      // Génère des badges depuis la catégorie et la description
                      _FeatureBadgesRow(product: product),

                      const SizedBox(height: 24),

                      // ── Boutons Panier + Favoris ──────────────────────
                      if (!isOwner)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              // ADD TO CART
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _primary.withOpacity(0.30),
                                        blurRadius: 14,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        Provider.of<CartProvider>(context, listen: false)
                                            .add(product),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.shopping_cart_outlined,
                                            color: Colors.white, size: 18),
                                        const SizedBox(width: 10),
                                        Text(
                                          'ADD TO CART  •  \$${price.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Favoris
                              Consumer<FavoriteProvider>(
                                builder: (context, fav, child) {
                                  final isFav = fav.isFavorite(id);
                                  return GestureDetector(
                                    onTap: () =>
                                        fav.toggleFavorite(currentUser!.id, id),
                                    child: Container(
                                      width: double.infinity,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isFav
                                            ? _red.withOpacity(0.06)
                                            : _surface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isFav
                                              ? _red.withOpacity(0.25)
                                              : _border,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            isFav
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            color:
                                                isFav ? _red : _textSub,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            isFav
                                                ? 'Retirer des favoris'
                                                : 'Ajouter aux favoris',
                                            style: TextStyle(
                                              color: isFav
                                                  ? _red
                                                  : _textSub,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // Livraison gratuite hint
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.local_shipping_outlined,
                                      size: 14, color: _green),
                                  SizedBox(width: 6),
                                  Text('Livraison via Escrow PLEXUS',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _green,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 28),
                      _Divider(),

                      // ── Description complète ──────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionTitle(title: 'Description'),
                            const SizedBox(height: 12),
                            Text(
                              desc.isNotEmpty ? desc : 'Aucune description.',
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.7,
                                  color: _textSub),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Vidéo (si dispo) ──────────────────────────────
                      if (videoUrl != null && videoUrl.isNotEmpty) ...[
                        _Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionTitle(title: 'Video de presentation'),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _border),
                                ),
                                child: Row(children: [
                                  const SizedBox(width: 16),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _accent.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.play_circle_outline_rounded,
                                        color: _accent, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: const [
                                        Text('Video disponible',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: _textMain,
                                                fontSize: 14)),
                                        SizedBox(height: 2),
                                        Text('Ouvrez le lien pour visionner',
                                            style: TextStyle(
                                                color: _textSub, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.open_in_new_rounded,
                                      size: 16, color: _textMuted),
                                  const SizedBox(width: 16),
                                ]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      _Divider(),

                      // ── Avis clients ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              _SectionTitle(title: 'Avis clients'),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _orange.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: _orange, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      avgRating > 0
                                          ? avgRating.toStringAsFixed(1)
                                          : '-',
                                      style: const TextStyle(
                                          color: _orange,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                            const SizedBox(height: 20),

                            // Formulaire d'avis
                            if (!isOwner) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Votre evaluation',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: _textSub,
                                            letterSpacing: 0.3)),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: List.generate(
                                        5,
                                        (i) => GestureDetector(
                                          onTap: () => setState(
                                              () => _userRating = i + 1.0),
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 4),
                                            child: Icon(
                                              i < _userRating
                                                  ? Icons.star_rounded
                                                  : Icons.star_outline_rounded,
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
                                      style: const TextStyle(
                                          color: _textMain, fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Partagez votre experience...',
                                        hintStyle: const TextStyle(
                                            color: _textMuted, fontSize: 13),
                                        filled: true,
                                        fillColor: Colors.white,
                                        contentPadding: const EdgeInsets.all(14),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: _border, width: 1.5)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: _border, width: 1.5)),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: _accent, width: 2)),
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
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                        child: const Text("Publier l'avis",
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Liste des avis
                            if (reviews.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _border),
                                ),
                                child: const Center(
                                  child: Text(
                                      'Soyez le premier a laisser un avis.',
                                      style: TextStyle(
                                          color: _textSub, fontSize: 14)),
                                ),
                              )
                            else
                              ...reviews.map((r) => _ReviewCard(review: r)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Feature badges row ───────────────────────────────────────────────────────
// Génère des badges contextuels selon la catégorie du produit
class _FeatureBadgesRow extends StatelessWidget {
  final Map<String, dynamic> product;
  const _FeatureBadgesRow({required this.product});

  static const Map<String, List<Map<String, dynamic>>> _featuresByCategory = {
    'Electronique' : [
      {'icon': Icons.battery_charging_full_rounded, 'label': 'Longue batterie'},
      {'icon': Icons.verified_outlined, 'label': 'Garantie 1 an'},
      {'icon': Icons.bolt_rounded, 'label': 'Livraison rapide'},
    ],
    'Mode' : [
      {'icon': Icons.dry_cleaning_outlined, 'label': 'Lavable'},
      {'icon': Icons.eco_outlined, 'label': 'Eco-friendly'},
      {'icon': Icons.straighten_rounded, 'label': 'Plusieurs tailles'},
    ],
    'Alimentation' : [
      {'icon': Icons.ac_unit_rounded, 'label': 'Produit frais'},
      {'icon': Icons.health_and_safety_outlined, 'label': 'Bio certifie'},
      {'icon': Icons.local_shipping_outlined, 'label': 'Livraison J+1'},
    ],
    'default' : [
      {'icon': Icons.verified_outlined, 'label': 'Qualite garantie'},
      {'icon': Icons.local_shipping_outlined, 'label': 'Livraison incluse'},
      {'icon': Icons.shield_outlined, 'label': 'Paiement securise'},
    ],
  };

  @override
  Widget build(BuildContext context) {
    final String cat = (product['category'] ?? 'default').toString();
    final features = _featuresByCategory[cat] ?? _featuresByCategory['default']!;

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: features.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final f = features[i];
          return Container(
            width: 120,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEEFF2), width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(f['icon'] as IconData,
                    size: 18, color: const Color(0xFF2563EB)),
                const SizedBox(height: 6),
                Text(
                  f['label'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Review card ──────────────────────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final dynamic review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final double rating = (review['rating'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEFF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: Color(0xFF1A237E), shape: BoxShape.circle),
              child: Center(
                child: Text(
                  (review['userName'] ?? 'A')[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(review['userName'] ?? 'Anonyme',
                    style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Row(children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 12,
                  ),
                )),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Text(review['comment'] ?? '',
              style: const TextStyle(
                  color: Color(0xFF64748B), fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      height: 8,
      color: const Color(0xFFF7F8FA),
      margin: const EdgeInsets.symmetric(vertical: 0));
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
          letterSpacing: -0.3,
        ),
      );
}