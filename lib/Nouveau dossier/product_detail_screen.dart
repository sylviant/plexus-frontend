import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/core/providers/favorite_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';
import 'package:plexus/presentation/widgets/related_product_card.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({required this.productId, super.key});
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<Map<String, dynamic>> _productFuture;
  final _commentCtrl  = TextEditingController();
  double _userRating  = 5;
  final _pageCtrl     = PageController();
  int   _currentPage  = 0;
  Future<List<dynamic>>? _relatedFuture;
  String? _relatedCategory;

  // ─── Sélection variante ───────────────────────────────────────────────────
  String?  _selectedColor;
  String?  _selectedSize;
  double?  _variantPrice;
  String?  _variantId;
  int?     _variantStock;
  bool     _loadingVariant    = false;
  bool     _variantUnavailable = false;
  List<String> _displayImages = [];

  // ─── Palette ──────────────────────────────────────────────────────────────
  static const Color _bg       = Color(0xFFFFFFFF);
  static const Color _surface  = Color(0xFFF7F8FA);
  static const Color _border   = Color(0xFFEEEFF2);
  static const Color _primary  = Color(0xFF1A237E);
  static const Color _accent   = Color(0xFF2563EB);
  static const Color _green    = Color(0xFF16A34A);
  static const Color _orange   = Color(0xFFF59E0B);
  static const Color _red      = Color(0xFFEF4444);
  static const Color _textMain = Color(0xFF0F172A);
  static const Color _textSub  = Color(0xFF64748B);
  static const Color _textMuted= Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _productFuture = _fetchProduct();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ─── Fetch ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _fetchProduct() async {
    final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/products/${widget.productId}'));
    if (res.statusCode == 200) {
      final product = json.decode(res.body) as Map<String, dynamic>;
      _displayImages = _extractProductImages(product);
      return product;
    }
    throw Exception('Produit non trouvé');
  }

  Future<List<dynamic>> _fetchRelated(String category, String currentId) async {
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/products'));
      if (res.statusCode == 200) {
        return (json.decode(res.body)['products'] as List)
            .where((p) => p['category'] == category && (p['_id'] ?? p['id']).toString() != currentId)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ─── Images ───────────────────────────────────────────────────────────────
  List<String> _extractProductImages(Map<String, dynamic> product) {
    final imgs = product['images'] as List? ?? [];
    final urls = imgs.map((i) => ApiConfig.getImageUrl(i.toString())).where((u) => u.isNotEmpty).toList();
    if (urls.isEmpty && product['thumbnail'] != null) {
      final t = ApiConfig.getImageUrl(product['thumbnail'].toString());
      if (t.isNotEmpty) return [t];
    }
    return urls;
  }

  List<String> _getVariantImages(Map<String, dynamic> product, String? color, String? size) {
    final variants = product['variants'] as List? ?? [];

    // Priorité 1 : combo exacte couleur + taille
    if (color != null && size != null) {
      final v = variants.firstWhere(
            (v) => v['color'] == color && v['size'] == size,
        orElse: () => null,
      );
      if (v != null && (v['images'] as List?)?.isNotEmpty == true) {
        return List<String>.from((v['images'] as List).map((i) => ApiConfig.getImageUrl(i.toString())));
      }
    }

    // Priorité 2 : variante par couleur
    if (color != null) {
      final v = variants.firstWhere(
            (v) => v['color'] == color && (v['size'] == null || v['size'] == ''),
        orElse: () => null,
      );
      if (v != null && (v['images'] as List?)?.isNotEmpty == true) {
        return List<String>.from((v['images'] as List).map((i) => ApiConfig.getImageUrl(i.toString())));
      }
      // Si couleur+taille, chercher n'importe quelle variante de cette couleur
      final anyColorVariant = variants.firstWhere(
            (v) => v['color'] == color && (v['images'] as List?)?.isNotEmpty == true,
        orElse: () => null,
      );
      if (anyColorVariant != null) {
        return List<String>.from((anyColorVariant['images'] as List).map((i) => ApiConfig.getImageUrl(i.toString())));
      }
    }

    // Priorité 3 : variante par taille
    if (size != null) {
      final v = variants.firstWhere(
            (v) => v['size'] == size && (v['images'] as List?)?.isNotEmpty == true,
        orElse: () => null,
      );
      if (v != null) {
        return List<String>.from((v['images'] as List).map((i) => ApiConfig.getImageUrl(i.toString())));
      }
    }

    // Priorité 4 : images générales du produit
    return _extractProductImages(product);
  }

  // ─── Logique de sélection ─────────────────────────────────────────────────

  void _onColorSelected(String color, Map<String, dynamic> product) {
    setState(() {
      _selectedColor       = color;
      _variantUnavailable  = false;
      // Mettre à jour les images immédiatement
      _displayImages = _getVariantImages(product, color, _selectedSize);
      _currentPage   = 0;
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    });

    final hasSizes = product['hasSizes'] == true;

    if (!hasSizes) {
      // Seulement couleurs → prix depuis la variante couleur
      final variants = product['variants'] as List? ?? [];
      final v = variants.firstWhere(
            (v) => v['color'] == color && v['available'] != false,
        orElse: () => null,
      );
      if (v != null) {
        setState(() {
          _variantPrice = (v['price'] as num).toDouble();
          _variantStock = (v['stock'] as num?)?.toInt();
          _variantId    = v['_id']?.toString();
        });
      } else {
        setState(() { _variantUnavailable = true; _variantId = null; });
      }
    } else if (_selectedSize != null) {
      // Couleurs + tailles → vérifier combo
      _fetchVariantFromBackend(product);
    }
  }

  void _onSizeSelected(String size, Map<String, dynamic> product) {
    setState(() {
      _selectedSize        = size;
      _variantUnavailable  = false;
      // Mettre à jour les images si pertinent
      _displayImages = _getVariantImages(product, _selectedColor, size);
      _currentPage   = 0;
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    });

    final hasColors = product['hasColors'] == true;

    if (!hasColors) {
      // Seulement tailles → prix depuis variante
      final variants = product['variants'] as List? ?? [];
      final v = variants.firstWhere(
            (v) => v['size'] == size && v['available'] != false,
        orElse: () => null,
      );
      if (v != null) {
        setState(() {
          _variantPrice = (v['price'] as num).toDouble();
          _variantStock = (v['stock'] as num?)?.toInt();
          _variantId    = v['_id']?.toString();
        });
      } else {
        setState(() { _variantUnavailable = true; _variantId = null; });
      }
    } else if (_selectedColor != null) {
      _fetchVariantFromBackend(product);
    }
  }

  Future<void> _fetchVariantFromBackend(Map<String, dynamic> product) async {
    setState(() => _loadingVariant = true);
    try {
      final id  = (product['_id'] ?? product['id']).toString();
      final uri = Uri.parse('${ApiConfig.baseUrl}/products/$id/variant'
          '?color=${Uri.encodeComponent(_selectedColor ?? '')}'
          '&size=${Uri.encodeComponent(_selectedSize ?? '')}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _variantId    = data['variantId']?.toString();
          _variantPrice = (data['price'] as num).toDouble();
          _variantStock = (data['stock'] as num?)?.toInt();
          _variantUnavailable = false;
          // Mettre à jour les images depuis le backend (priorité)
          final imgs = data['images'] as List? ?? [];
          if (imgs.isNotEmpty) {
            _displayImages = imgs.map((i) => ApiConfig.getImageUrl(i.toString())).where((u) => u.isNotEmpty).toList();
          }
        });
      } else {
        setState(() { _variantUnavailable = true; _variantId = null; });
      }
    } catch (_) {
      setState(() { _variantUnavailable = true; });
    } finally {
      if (mounted) setState(() => _loadingVariant = false);
    }
  }

  // ─── Disponibilité locale ─────────────────────────────────────────────────

  bool _isColorAvailable(Map<String, dynamic> product, String color) {
    final variants  = product['variants'] as List? ?? [];
    final hasSizes  = product['hasSizes'] == true;
    if (_selectedSize != null && hasSizes) {
      return variants.any((v) => v['color'] == color && v['size'] == _selectedSize && v['available'] != false);
    }
    return variants.any((v) => v['color'] == color && v['available'] != false);
  }

  bool _isSizeAvailable(Map<String, dynamic> product, String size) {
    final variants  = product['variants'] as List? ?? [];
    final hasColors = product['hasColors'] == true;
    if (_selectedColor != null && hasColors) {
      return variants.any((v) => v['size'] == size && v['color'] == _selectedColor && v['available'] != false);
    }
    return variants.any((v) => v['size'] == size && v['available'] != false);
  }

  // ─── Listes uniques ───────────────────────────────────────────────────────

  List<String> _uniqueColors(Map<String, dynamic> product) {
    final variants = product['variants'] as List? ?? [];
    final seen = <String>{};
    return variants
        .map((v) => v['color']?.toString() ?? '')
        .where((c) => c.isNotEmpty && seen.add(c))
        .toList();
  }

  List<String> _uniqueSizes(Map<String, dynamic> product) {
    final variants = product['variants'] as List? ?? [];
    final seen = <String>{};
    return variants
        .map((v) => v['size']?.toString() ?? '')
        .where((s) => s.isNotEmpty && seen.add(s))
        .toList();
  }

  // ─── Ajouter au panier ────────────────────────────────────────────────────
  void _handleAddToCart(BuildContext ctx, Map<String, dynamic> product) {
    final hasColors = product['hasColors'] == true;
    final hasSizes  = product['hasSizes']  == true;

    if (hasColors && _selectedColor == null) {
      _showSnack('Veuillez sélectionner une couleur.', Colors.orange, Icons.warning); return;
    }
    if (hasSizes && _selectedSize == null) {
      _showSnack('Veuillez sélectionner une taille.', Colors.orange, Icons.warning); return;
    }
    if ((hasColors || hasSizes) && (_variantId == null || _variantUnavailable)) {
      _showSnack('Cette variante est indisponible.', _red, Icons.block); return;
    }

    Provider.of<CartProvider>(ctx, listen: false).add(
      product,
      variantId:    _variantId,
      size:         _selectedSize,
      color:        _selectedColor,
      variantPrice: _variantPrice,
      variantImage: _displayImages.isNotEmpty ? _displayImages.first : null,
    );

    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
        SizedBox(width: 8),
        Text('Ajouté au panier'),
      ]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showSnack(String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [Icon(icon, color: Colors.white, size: 16), const SizedBox(width: 8), Expanded(child: Text(msg, style: const TextStyle(color: Colors.white)))]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ─── Review ───────────────────────────────────────────────────────────────
  Future<void> _submitReview() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null || _commentCtrl.text.isEmpty) return;
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/reviews'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'productId': widget.productId, 'userId': user.id, 'userName': user.firstName, 'rating': _userRating, 'comment': _commentCtrl.text}),
    );
    _commentCtrl.clear();
    setState(() => _productFuture = _fetchProduct());
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).currentUser;

    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _productFuture,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2));
          }
          if (!snap.hasData || snap.hasError) {
            return const Center(child: Text('Erreur de chargement.', style: TextStyle(color: _textSub)));
          }

          final product   = snap.data!;
          final String id = (product['_id'] ?? product['id']).toString();
          final title     = product['title']       ?? '';
          final desc      = product['description'] ?? '';
          final double basePrice = (product['price']    as num? ?? 0).toDouble();
          final double oldPrice  = (product['oldPrice'] as num? ?? 0).toDouble();
          final List reviews     = product['reviews'] ?? [];
          final bool isOwner     = currentUser?.id == product['sellerId'];
          final bool hasColors   = product['hasColors'] == true;
          final bool hasSizes    = product['hasSizes']  == true;
          final bool hasVariants = hasColors || hasSizes;
          final String? videoUrl = product['video'] != null && product['video'].toString().isNotEmpty
              ? ApiConfig.getImageUrl(product['video'].toString())
              : null;

          final colors = hasColors ? _uniqueColors(product) : <String>[];
          final sizes  = hasSizes  ? _uniqueSizes(product)  : <String>[];

          final double displayPrice = _variantPrice ?? basePrice;
          final bool   hasDiscount  = oldPrice > basePrice && oldPrice > 0 && _variantPrice == null;
          final int    discountPct  = hasDiscount ? (((oldPrice - basePrice) / oldPrice) * 100).round() : 0;

          if (_displayImages.isEmpty) _displayImages = _extractProductImages(product);

          double avgRating = 0;
          if (reviews.isNotEmpty) {
            avgRating = reviews.fold<double>(0, (s, r) => s + ((r['rating'] as num?)?.toDouble() ?? 0)) / reviews.length;
          }

          if (_relatedCategory != product['category']) {
            _relatedCategory = product['category']?.toString();
            _relatedFuture   = _fetchRelated(_relatedCategory ?? '', id);
          }

          return CustomScrollView(
            slivers: [
              // ── AppBar + galerie ──────────────────────────────────────
              SliverAppBar(
                expandedHeight: 340,
                pinned: true,
                backgroundColor: _bg,
                elevation: 0,
                scrolledUnderElevation: 1,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8)]),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: _textMain),
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: GestureDetector(
                      onTap: () => context.go('/cart'),
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8)]),
                        child: const Padding(padding: EdgeInsets.all(8),
                            child: Icon(Icons.shopping_bag_outlined, size: 20, color: _textMain)),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(children: [
                    _displayImages.isEmpty
                        ? Container(color: _surface, child: const Center(child: Icon(Icons.image_outlined, size: 80, color: _textMuted)))
                        : PageView.builder(
                      controller: _pageCtrl,
                      itemCount: _displayImages.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (_, i) => GestureDetector(
                        // ← TAP → ouvre la galerie plein écran
                        onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            opaque: false,
                            pageBuilder: (_, _, _) => _FullScreenGallery(
                              images:       _displayImages,
                              initialIndex: _currentPage,
                            ),
                            transitionsBuilder: (_, anim, _, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: const Duration(milliseconds: 300),
                          ),
                        ),
                        child: Container(
                          color: const Color(0xFFF7F8FA),
                          child: Image.network(
                            _displayImages[i],
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_outlined,
                                  size: 60, color: Color(0xFF94A3B8)),
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (hasDiscount)
                      Positioned(
                        top: 60, right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(20)),
                          child: Text('SAVE $discountPct%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),

                    if (_displayImages.length > 1)
                      Positioned(
                        bottom: 14, left: 0, right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_displayImages.length, (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _currentPage == i ? 20 : 6, height: 6,
                            decoration: BoxDecoration(
                              color: _currentPage == i ? _accent : _textMuted.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )),
                        ),
                      ),
                  ]),
                ),
              ),

              // ── Contenu ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── En-tête ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product['category'] != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                              child: Text((product['category'] as String).toUpperCase(),
                                  style: const TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                            ),
                          const SizedBox(height: 8),
                          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textMain, height: 1.2, letterSpacing: -0.3)),
                          const SizedBox(height: 6),
                          if (desc.isNotEmpty)
                            Text(desc.length > 100 ? '${desc.substring(0, 100)}...' : desc,
                                style: const TextStyle(fontSize: 13, color: _textSub, height: 1.4)),
                          const SizedBox(height: 12),
                          Row(children: [
                            ...List.generate(5, (i) => Icon(
                              i < avgRating.floor() ? Icons.star_rounded : (i < avgRating ? Icons.star_half_rounded : Icons.star_outline_rounded),
                              color: _orange, size: 16,
                            )),
                            const SizedBox(width: 6),
                            Text(avgRating > 0 ? '${avgRating.toStringAsFixed(1)} (${reviews.length})' : 'Aucun avis',
                                style: const TextStyle(color: _textSub, fontSize: 12)),
                          ]),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    _Divider(),

                    // ── Prix ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text('\$${displayPrice.toStringAsFixed(2)}',
                              key: ValueKey(displayPrice),
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _textMain, letterSpacing: -1),
                            ),
                          ),
                          if (hasDiscount) ...[
                            const SizedBox(width: 10),
                            Text('\$${oldPrice.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _textMuted, decoration: TextDecoration.lineThrough)),
                          ],
                          if (_loadingVariant) ...[
                            const SizedBox(width: 10),
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
                          ],
                          if (_variantStock != null && _variantStock! <= 5 && _variantStock! > 0) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: _red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                              child: Text('Plus que $_variantStock !',
                                  style: const TextStyle(color: _red, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ],
                          const Spacer(),
                          if (isOwner)
                            GestureDetector(
                              onTap: () => context.push('/profile/add-product', extra: product),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(color: _orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10), border: Border.all(color: _orange.withValues(alpha: 0.3))),
                                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                                  Icon(Icons.edit_outlined, size: 14, color: _orange),
                                  SizedBox(width: 5),
                                  Text('Modifier', style: TextStyle(color: _orange, fontWeight: FontWeight.w600, fontSize: 13)),
                                ]),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ── Sélecteur variantes ──────────────────────────────
                    if (hasVariants) ...[
                      const SizedBox(height: 20),
                      _Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: _buildVariantSelector(product, colors, sizes),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Feature badges ────────────────────────────────────
                    _FeatureBadgesRow(product: product),
                    const SizedBox(height: 24),

                    // ── Boutons action ─────────────────────────────────────
                    if (!isOwner)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                              child: SizedBox(
                                height: 54,
                                child: OutlinedButton(
                                  onPressed: () => _handleAddToCart(context, product),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: _primary, width: 1.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                                    Icon(Icons.shopping_cart_outlined, color: _primary, size: 18),
                                    SizedBox(width: 8),
                                    Flexible(child: Text('Ajouter au panier', overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: _primary, fontWeight: FontWeight.w700, fontSize: 13))),
                                  ]),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 54,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [_primary, Color(0xFF3949AB)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 5))],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () => context.push('/cart/payment', extra: {'singleProduct': product}),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                                      Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                                      SizedBox(width: 8),
                                      Flexible(child: Text('Commander', overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                          ]),

                          const SizedBox(height: 10),

                          Consumer<FavoriteProvider>(
                            builder: (_, fav, _) {
                              final isFav = fav.isFavorite(id);
                              return GestureDetector(
                                onTap: () => fav.toggleFavorite(currentUser!.id, id),
                                child: Container(
                                  width: double.infinity, height: 48,
                                  decoration: BoxDecoration(
                                    color: isFav ? _red.withValues(alpha: 0.06) : _surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: isFav ? _red.withValues(alpha: 0.25) : _border, width: 1.5),
                                  ),
                                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isFav ? _red : _textSub, size: 18),
                                    const SizedBox(width: 8),
                                    Text(isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                                        style: TextStyle(color: isFav ? _red : _textSub, fontWeight: FontWeight.w600, fontSize: 13)),
                                  ]),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                            Icon(Icons.local_shipping_outlined, size: 14, color: _green),
                            SizedBox(width: 6),
                            Text('Livraison via Escrow PLEXUS', style: TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w500)),
                          ]),
                        ]),
                      ),

                    const SizedBox(height: 28),

                    if (product['sellerId'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GestureDetector(
                          onTap: () => context.push('/seller/${product['sellerId']}'),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: Row(children: [
                              Container(
                                width: 40, height: 40,
                                decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                                child: Center(
                                  child: Text(
                                    (product['sellerName'] ?? '?').toString().isNotEmpty
                                        ? product['sellerName'][0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Text('Vendu par', style: TextStyle(fontSize: 11, color: _textMuted)),
                                  Text(product['sellerName'] ?? 'Vendeur', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textMain)),
                                ]),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _textMuted),
                            ]),
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),
                    _Divider(),

                    // ── Description ────────────────────────────────────────
                    // ── Description ────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _SectionTitle(title: 'Description'),
                        const SizedBox(height: 12),
                        Text(desc.isNotEmpty ? desc : 'Aucune description.',
                            style: const TextStyle(fontSize: 14, height: 1.7, color: _textSub)),
                      ]),
                    ),

                    // ── Vidéo du produit ───────────────────────────────────
                    if (videoUrl != null && videoUrl.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _SectionTitle(title: 'Vidéo du produit'),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: double.infinity,
                              height: 220,
                              color: Colors.black,
                              child: Stack(children: [
                                // Lecteur vidéo HTML5
                                _VideoPlayerWidget(url: videoUrl),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 28),
                    _Divider(),

                    // ── Avis ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          _SectionTitle(title: 'Avis clients'),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: _orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.star_rounded, color: _orange, size: 14),
                              const SizedBox(width: 4),
                              Text(avgRating > 0 ? avgRating.toStringAsFixed(1) : '-',
                                  style: const TextStyle(color: _orange, fontWeight: FontWeight.w700, fontSize: 12)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 20),

                        if (!isOwner) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Votre évaluation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _textSub)),
                              const SizedBox(height: 10),
                              Row(children: List.generate(5, (i) => GestureDetector(
                                onTap: () => setState(() => _userRating = i + 1.0),
                                child: Padding(padding: const EdgeInsets.only(right: 4),
                                    child: Icon(i < _userRating ? Icons.star_rounded : Icons.star_outline_rounded, color: _orange, size: 28)),
                              ))),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _commentCtrl,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText: 'Partagez votre expérience...',
                                  hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
                                  filled: true, fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.all(14),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border, width: 1.5)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border, width: 1.5)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent, width: 2)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity, height: 46,
                                child: ElevatedButton(
                                  onPressed: _submitReview,
                                  style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                  child: const Text("Publier l'avis", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (reviews.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                            child: const Center(child: Text('Soyez le premier à laisser un avis.', style: TextStyle(color: _textSub, fontSize: 14))),
                          )
                        else
                          ...reviews.map((r) => _ReviewCard(review: r)),
                      ]),
                    ),

                    // ── Articles similaires ────────────────────────────────
                    _Divider(),
                    Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0), child: _SectionTitle(title: 'Articles similaires')),
                    const SizedBox(height: 16),
                    FutureBuilder<List<dynamic>>(
                      future: _relatedFuture,
                      builder: (_, relSnap) {
                        if (relSnap.connectionState == ConnectionState.waiting) {
                          return const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2)));
                        }
                        final related = relSnap.data ?? [];
                        if (related.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: MasonryGridView.count(
                            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
                            itemCount: related.length,
                            itemBuilder: (_, i) => RelatedProductCard(product: related[i]),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Sélecteur variantes ──────────────────────────────────────────────────
  Widget _buildVariantSelector(Map<String, dynamic> product, List<String> colors, List<String> sizes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Couleurs ──────────────────────────────────────────────────────
        if (colors.isNotEmpty) ...[
          const Text('COULEUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textSub, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: colors.map((color) {
              final available = _isColorAvailable(product, color);
              final selected  = _selectedColor == color;

              // Récupérer la miniature de la couleur
              final variants = product['variants'] as List? ?? [];
              final colorVar = variants.firstWhere(
                    (v) => v['color'] == color && (v['images'] as List?)?.isNotEmpty == true,
                orElse: () => null,
              );
              final thumbUrl = colorVar != null
                  ? ApiConfig.getImageUrl((colorVar['images'] as List).first.toString())
                  : null;

              return GestureDetector(
                onTap: available ? () => _onColorSelected(color, product) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.fromLTRB(thumbUrl != null ? 4 : 14, 6, 14, 6),
                  decoration: BoxDecoration(
                    color: selected ? _primary.withValues(alpha: 0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: !available ? Colors.grey[300]! : selected ? _primary : _border,
                      width: selected ? 2.5 : 1.5,
                    ),
                    boxShadow: selected ? [BoxShadow(color: _primary.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 3))] : [],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (thumbUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(thumbUrl, width: 30, height: 30, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(color,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: !available ? Colors.grey[400] : selected ? _primary : _textMain,
                        decoration: !available ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (selected) ...[const SizedBox(width: 6), const Icon(Icons.check_circle, color: _primary, size: 14)],
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // ── Tailles ───────────────────────────────────────────────────────
        if (sizes.isNotEmpty) ...[
          const Text('TAILLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textSub, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: sizes.map((size) {
              final available = _isSizeAvailable(product, size);
              final selected  = _selectedSize == size;
              return GestureDetector(
                onTap: available ? () => _onSizeSelected(size, product) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? _primary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: !available ? Colors.grey[300]! : selected ? _primary : _border,
                      width: selected ? 2 : 1.5,
                    ),
                    boxShadow: selected ? [BoxShadow(color: _primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3))] : [],
                  ),
                  child: Text(size,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: !available ? Colors.grey[400] : selected ? Colors.white : _textMain,
                      decoration: !available ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // ── Résumé ────────────────────────────────────────────────────────
        if (_selectedColor != null || _selectedSize != null) ...[
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_variantUnavailable || _variantId == null)
                  ? _red.withValues(alpha: 0.05)
                  : _green.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_variantUnavailable || _variantId == null)
                    ? _red.withValues(alpha: 0.3)
                    : _green.withValues(alpha: 0.3),
              ),
            ),
            child: Row(children: [
              Icon(
                _variantUnavailable || _variantId == null ? Icons.block : Icons.check_circle_outline,
                color: _variantUnavailable || _variantId == null ? _red : _green,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _variantUnavailable || _variantId == null
                      ? 'Combinaison indisponible'
                      : 'Sélection : ${[if (_selectedColor != null) _selectedColor, if (_selectedSize != null) _selectedSize].join(' / ')}',
                  style: TextStyle(
                    color: _variantUnavailable || _variantId == null ? _red : _green,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

// ─── Lecteur vidéo ────────────────────────────────────────────────────────────
class _VideoPlayerWidget extends StatelessWidget {
  final String url;
  const _VideoPlayerWidget({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Sur web : ouvrir dans un nouvel onglet
        // Sur mobile : utiliser video_player si disponible
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(color: Colors.black87),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 12),
            const Text('Appuyez pour lire la vidéo',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _FeatureBadgesRow extends StatelessWidget {
  final Map<String, dynamic> product;
  const _FeatureBadgesRow({required this.product});
  @override
  Widget build(BuildContext context) {
    const features = [
      {'icon': Icons.verified_outlined,       'label': 'Qualité garantie'},
      {'icon': Icons.local_shipping_outlined, 'label': 'Livraison incluse'},
      {'icon': Icons.shield_outlined,         'label': 'Paiement sécurisé'},
    ];
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: features.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = features[i];
          return Container(
            width: 120,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEEFF2), width: 1.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(f['icon'] as IconData, size: 18, color: const Color(0xFF2563EB)),
              const SizedBox(height: 6),
              Text(f['label'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A), height: 1.2)),
            ]),
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final dynamic review;
  const _ReviewCard({required this.review});
  @override
  Widget build(BuildContext context) {
    final double rating = (review['rating'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFEEEFF2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle),
              child: Center(child: Text((review['userName'] ?? 'A')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(review['userName'] ?? 'Anonyme', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 14)),
            Row(children: List.generate(5, (i) => Icon(
              i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: const Color(0xFFF59E0B), size: 12,
            ))),
          ])),
        ]),
        const SizedBox(height: 10),
        Text(review['comment'] ?? '', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.5)),
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(height: 8, color: const Color(0xFFF7F8FA));
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.3));
}

// ─── Galerie plein écran ──────────────────────────────────────────────────────
class _FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int          initialIndex;

  const _FullScreenGallery({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late int              _current;
  late PageController   _pageCtrl;

  @override
  void initState() {
    super.initState();
    _current  = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [

          // ── Galerie swipeable ────────────────────────────────────────
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    widget.images[i],
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                              : null,
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white38,
                        size: 60),
                  ),
                ),
              ),
            ),
          ),

          // ── Bouton fermer ────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),

          // ── Compteur ─────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_current + 1} / ${widget.images.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

          // ── Miniatures en bas ────────────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 0, right: 0,
            child: SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.images.length,
                itemBuilder: (_, i) {
                  final selected = _current == i;
                  return GestureDetector(
                    onTap: () => _pageCtrl.animateToPage(i,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56, height: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white24,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        widget.images[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                            color: Colors.grey[900],
                            child: const Icon(Icons.image_outlined,
                                color: Colors.white38, size: 20)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}