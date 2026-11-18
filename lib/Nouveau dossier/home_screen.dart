import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/models/user_type.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:plexus/presentation/widgets/category_list.dart';
import 'package:plexus/presentation/widgets/product_card.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';

// ─── Constantes globales ──────────────────────────────────────────────────────
const Color _primary    = Color(0xFF1A237E);
const Color _primaryMid = Color(0xFF3949AB);
const Color _surface    = Color(0xFFF4F6FB);
const Color _border     = Color(0xFFE2E8F0);
const Color _textMain   = Color(0xFF0F172A);
const Color _textSub    = Color(0xFF64748B);

// ─── Placeholders animés pour la barre de recherche ──────────────────────────
const List<String> _searchPlaceholders = [
  'Rechercher un article...',
  'Nouvelle tendance de bijoux',
  'Prix de l\'iPhone 15 Pro Max',
  'Chaussures de sport',
  'Téléphones Samsung',
  'Robes pour femmes',
  'Ordinateurs portables',
  'Meilleurs écouteurs Bluetooth',
  'Nouveautés électroniques',
  'Accessoires automobiles',
  'Montres de luxe',
  'Promotions du jour',
  'Air jordan 1',
];

class HomeScreen extends StatefulWidget {
  final String? initialCategory;
  const HomeScreen({this.initialCategory, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ─── Données ──────────────────────────────────────────────────────────────
  List<dynamic> _allProducts      = [];
  List<dynamic> _filteredProducts = [];
  final List<dynamic> _shuffledProducts = [];
  bool _isLoading = true;
  String? _error;

  // ─── Search ───────────────────────────────────────────────────────────────
  final _searchController     = TextEditingController();
  final _searchFocusNode      = FocusNode();
  bool _searchFocused         = false;
  bool _showSuggestions       = false;
  List<String> _popularTerms  = [];
  List<String> _popularCats   = [];

  // ─── Placeholder animé ────────────────────────────────────────────────────
  int    _placeholderIndex  = 0;
  double _placeholderOpacity = 1.0;
  Timer? _placeholderTimer;

  // ─── Catégorie + scroll ───────────────────────────────────────────────────
  late String _selectedCategory;
  final _scrollController = ScrollController();
  bool _isVisible = true;

  // ─── Ordre aléatoire (stable pendant la session) ─────────────────────────
  List<int> _shuffleOrder = [];
  final _rng = Random();

  // ─── Cards d'inspiration (positions) ─────────────────────────────────────
  // On insère une carte d'inspiration tous les N produits (4-6 lignes × 2 cols)
  static const int _minInsert = 8;   // 4 lignes × 2
  static const int _maxInsert = 12;  // 6 lignes × 2
  List<int> _inspirationPositions = [];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Tout';
    _fetchProducts();
    _startPlaceholderAnimation();

    _searchFocusNode.addListener(() {
      setState(() {
        _searchFocused   = _searchFocusNode.hasFocus;
        _showSuggestions = _searchFocusNode.hasFocus && _searchController.text.isEmpty;
      });
    });

    _scrollController.addListener(() {
      final dir = _scrollController.position.userScrollDirection;
      if (dir == ScrollDirection.reverse && _isVisible) {
        setState(() => _isVisible = false);
      } else if (dir == ScrollDirection.forward && !_isVisible) {
        setState(() => _isVisible = true);
      }
    });
  }





  @override
  void dispose() {
    _placeholderTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Animation placeholder ────────────────────────────────────────────────
  void _startPlaceholderAnimation() {
    _placeholderTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _placeholderOpacity = 0.0);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _placeholderIndex = (_placeholderIndex + 1) % _searchPlaceholders.length;
          _placeholderOpacity = 1.0;
        });
      });
    });
  }

  // ─── Fetch produits ───────────────────────────────────────────────────────
  Future<void> _fetchProducts() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/products'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          final products = data['products'] as List<dynamic>;
          setState(() {
            _allProducts = products;
            _isLoading   = false;
          });
          _buildShuffleOrder(products.length);
          _extractPopularTerms(products);
          _applyFilters();
        }
      } else {
        if (mounted) setState(() { _error = 'Erreur serveur'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Connexion impossible'; _isLoading = false; });
    }
  }

  // ─── Ordre aléatoire stable ───────────────────────────────────────────────
  void _buildShuffleOrder(int length) {
    _shuffleOrder = List.generate(length, (i) => i)..shuffle(_rng);
    _computeInspirationPositions();
  }

  // ─── Positions des cartes d'inspiration ──────────────────────────────────
  void _computeInspirationPositions() {
    _inspirationPositions = [];
    int cursor = 0;
    while (cursor < _shuffleOrder.length) {
      final gap = _minInsert + _rng.nextInt(_maxInsert - _minInsert + 1);
      cursor += gap;
      if (cursor < _shuffleOrder.length) {
        _inspirationPositions.add(cursor);
      }
    }
  }

  // ─── Suggestions de recherche ─────────────────────────────────────────────
  void _extractPopularTerms(List<dynamic> products) {
    final titles = products
        .map((p) => (p['title'] ?? '').toString())
        .where((t) => t.isNotEmpty)
        .take(20)
        .toList();
    final cats = products
        .map((p) => (p['category'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toSet()
        .take(8)
        .toList();
    setState(() {
      _popularTerms = titles;
      _popularCats  = cats;
    });
  }

  // ─── Filtres ──────────────────────────────────────────────────────────────
  void _applyFilters() {
    final query       = _searchController.text.toLowerCase().trim();
    final selectedCat = _selectedCategory.toLowerCase().trim();

    List<dynamic> base = _allProducts.where((p) {
      final matchesSearch   = query.isEmpty || (p['title'] ?? '').toString().toLowerCase().contains(query);
      final matchesCategory = selectedCat == 'tout' ||
          (p['category'] ?? '').toString().toLowerCase() == selectedCat;
      return matchesSearch && matchesCategory;
    }).toList();

    // Appliquer l'ordre aléatoire stable
    if (_shuffleOrder.isNotEmpty && query.isEmpty) {
      final indexed = base.asMap().entries.toList();
      final ids = base.map((p) => (p['_id'] ?? p['id']).toString()).toList();
      // Trier selon l'ordre de _shuffleOrder
      base = List<dynamic>.from(base);
      base.sort((a, b) {
        final ia = ids.indexOf((a['_id'] ?? a['id']).toString());
        final ib = ids.indexOf((b['_id'] ?? b['id']).toString());
        final oa = ia < _shuffleOrder.length ? _shuffleOrder.indexOf(ia) : 999999;
        final ob = ib < _shuffleOrder.length ? _shuffleOrder.indexOf(ib) : 999999;
        return oa.compareTo(ob);
      });
    }

    setState(() => _filteredProducts = base);
  }

  // ─── Construction de la liste mixée (produits + inspirations) ────────────
  List<_HomeItem> _buildItemList() {
    final items = <_HomeItem>[];
    int prodIdx      = 0;
    int inspCount    = 0;

    for (int i = 0; i < _filteredProducts.length; i++) {
      // Insérer une carte d'inspiration si on est à une position marquée
      if (inspCount < _inspirationPositions.length &&
          i == _inspirationPositions[inspCount]) {
        items.add(_HomeItem.inspiration(inspCount));
        inspCount++;
      }
      items.add(_HomeItem.product(_filteredProducts[i]));
    }
    return items;
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _searchFocusNode.unfocus();
        setState(() => _showSuggestions = false);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  // ── Header ───────────────────────────────────────────
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bienvenue sur',
                                style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Row(children: const [
                              Text('PLEXUS',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _primary, letterSpacing: 3)),
                              SizedBox(width: 6),
                              Text('MARKET',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, color: _primaryMid, letterSpacing: 2)),
                            ]),
                          ],
                        ),
                        const Spacer(),
                        _NotifButton(),
                      ],
                    ),
                  ),

                  // ── Barre de recherche animée ────────────────────────
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    height: _isVisible ? 64 : 0,
                    curve: Curves.easeInOut,
                    color: Colors.white,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: _isVisible ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _searchFocused ? _primary : _border,
                              width: _searchFocused ? 2 : 1.5,
                            ),
                          ),
                          child: TextField(
                            controller:  _searchController,
                            focusNode:   _searchFocusNode,
                            onChanged:   (v) {
                              _applyFilters();
                              setState(() => _showSuggestions = v.isEmpty && _searchFocused);
                            },
                            onTap:       () => setState(() => _showSuggestions = _searchController.text.isEmpty),
                            style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: _searchPlaceholders[_placeholderIndex],
                              hintStyle: TextStyle(color: _textSub.withValues(alpha: 0.5), fontSize: 14),
                              prefixIcon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Icon(
                                  _searchFocused ? Icons.search_rounded : Icons.search_rounded,
                                  key: ValueKey(_searchFocused),
                                  color: _searchFocused ? _primary : _textSub,
                                  size: 20,
                                ),
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  _applyFilters();
                                  setState(() => _showSuggestions = true);
                                },
                                child: const Icon(Icons.close_rounded, color: _textSub, size: 18),
                              )
                                  : Padding(
                                padding: const EdgeInsets.all(8),
                                child: Container(
                                  decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.tune_rounded, color: Colors.white, size: 16),
                                ),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Categories ───────────────────────────────────────
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: _isVisible ? 106 : 0,
                    curve: Curves.easeInOut,
                    color: Colors.white,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: _isVisible ? 1 : 0,
                      child: CategoryList(
                        selectedCategory: _selectedCategory,
                        onCategorySelected: (cat) {
                          setState(() => _selectedCategory = cat);
                          _applyFilters();
                        },
                      ),
                    ),
                  ),

                  // Séparateur
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                  ),

                  // ── Corps ────────────────────────────────────────────
                  Expanded(
                    child: _isLoading
                        ? _buildSkeletonGrid()
                        : _error != null
                        ? _buildErrorState()
                        : RefreshIndicator(
                      onRefresh: _fetchProducts,
                      color: _primary,
                      child: _buildProductList(),
                    ),
                  ),
                ],
              ),

              // ── Overlay suggestions ──────────────────────────────────
              if (_showSuggestions)
                Positioned(
                  top: _isVisible ? 190 : 90,
                  left: 0, right: 0,
                  child: _buildSuggestionsOverlay(),
                ),
            ],
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: Consumer<UserProvider>(
            builder: (context, user, child) {
              if (user.userType != UserType.seller) return const SizedBox.shrink();
              return Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_primary, _primaryMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: FloatingActionButton.extended(
                  onPressed: () => context.push('/profile/add-product'),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text('VENDRE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Liste produits + inspirations ───────────────────────────────────────
  Widget _buildProductList() {
    if (_filteredProducts.isEmpty) {
      return CustomScrollView(
        controller: _scrollController,
        slivers: [
          const SliverToBoxAdapter(child: PromoBannerCarousel()),
          _buildSectionTitle('Pour vous'),
          SliverToBoxAdapter(child: _buildEmptySearch()),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      );
    }

    final items = _buildItemList();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Bannières promo
        const SliverToBoxAdapter(child: PromoBannerCarousel()),
        _buildSectionTitle('Pour vous'),

        // Grille mixée
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, i) {
                final item = items[i];

                // Carte d'inspiration (pleine largeur)
                if (item.isInspiration) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _InspirationCard(
                      products: _allProducts,
                      seed: item.inspirationIndex!,
                    ),
                  );
                }

                // Rangée de 2 produits
                final leftIdx  = i - items.take(i).where((x) => x.isInspiration).length;
                // On utilise une grille manuelle par paires
                return const SizedBox.shrink(); // géré ci-dessous
              },
              childCount: 0, // On override avec la grille ci-dessous
            ),
          ),
        ),

        // Grille manuelle pour gérer les insertions d'inspiration
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: _MixedGridSliver(items: items, allProducts: _allProducts),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  // ─── Suggestions overlay ──────────────────────────────────────────────────
  Widget _buildSuggestionsOverlay() {
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      color: Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 320),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Produits populaires
              if (_popularTerms.isNotEmpty) ...[
                const Text('Produits populaires',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textSub, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _popularTerms.take(6).map((t) => GestureDetector(
                    onTap: () {
                      _searchController.text = t;
                      _applyFilters();
                      _searchFocusNode.unfocus();
                      setState(() => _showSuggestions = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.trending_up_rounded, size: 12, color: _primary),
                        const SizedBox(width: 5),
                        Text(t, style: const TextStyle(fontSize: 12, color: _textMain, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Catégories populaires
              if (_popularCats.isNotEmpty) ...[
                const Text('Catégories',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textSub, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _popularCats.map((c) => GestureDetector(
                    onTap: () {
                      _searchFocusNode.unfocus();
                      setState(() {
                        _selectedCategory = c;
                        _showSuggestions  = false;
                      });
                      _applyFilters();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.category_outlined, size: 12, color: _primary),
                        const SizedBox(width: 5),
                        Text(c, style: const TextStyle(fontSize: 12, color: _primary, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  )).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildSkeletonGrid() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _SkeletonBox(height: 168, radius: 20),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: _SkeletonBox(width: 120, height: 16, radius: 8),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.72,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
                  (_, _) => Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Expanded(flex: 3, child: _SkeletonBox(radius: 12, isFull: true)),
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SkeletonBox(width: 60, height: 12, radius: 6),
                          const SizedBox(height: 6),
                          _SkeletonBox(height: 10, radius: 6, isFull: true),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
              childCount: 6,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  // ─── Error + Empty ────────────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.08), blurRadius: 20)]),
            child: const Icon(Icons.wifi_off_rounded, size: 36, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 20),
          Text(_error!, style: const TextStyle(color: _textMain, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          const Text('Vérifiez votre connexion internet.', style: TextStyle(color: _textSub, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchProducts,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
            label: const Text('Réessayer', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 40),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 16),
          Text(
            'Aucun résultat pour\n"${_searchController.text}"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textMain, fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 6),
          const Text('Essayez un autre terme ou une autre catégorie.',
              textAlign: TextAlign.center, style: TextStyle(color: _textSub, fontSize: 12)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        child: Row(children: [
          Container(width: 3, height: 16,
              decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _textMain, letterSpacing: -0.3)),
          const Spacer(),
          Text('Voir tout', style: TextStyle(color: _primaryMid, fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ─── Modèle item (produit ou inspiration) ─────────────────────────────────────
class _HomeItem {
  final bool isInspiration;
  final dynamic product;
  final int? inspirationIndex;

  const _HomeItem._({required this.isInspiration, this.product, this.inspirationIndex});

  factory _HomeItem.product(dynamic p)       => _HomeItem._(isInspiration: false, product: p);
  factory _HomeItem.inspiration(int index)   => _HomeItem._(isInspiration: true, inspirationIndex: index);
}

// ─── Sliver grille mixée ──────────────────────────────────────────────────────
class _MixedGridSliver extends StatelessWidget {
  final List<_HomeItem> items;
  final List<dynamic>   allProducts;

  const _MixedGridSliver({required this.items, required this.allProducts});

  @override
  Widget build(BuildContext context) {
    // On regroupe les produits par paires et on insère les cartes d'inspiration
    final rows = <Widget>[];
    int i = 0;

    while (i < items.length) {
      final item = items[i];

      if (item.isInspiration) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _InspirationCard(products: allProducts, seed: item.inspirationIndex!),
        ));
        i++;
      } else {
        // Paire de produits
        final left  = item.product;
        final right = (i + 1 < items.length && !items[i + 1].isInspiration)
            ? items[i + 1].product
            : null;

        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: ProductCard(product: left)),
              const SizedBox(width: 14),
              Expanded(child: right != null ? ProductCard(product: right) : const SizedBox()),
            ],
          ),
        ));
        i += right != null ? 2 : 1;
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (_, i) => rows[i],
        childCount: rows.length,
      ),
    );
  }
}

// ─── Carte d'inspiration ──────────────────────────────────────────────────────
class _InspirationCard extends StatefulWidget {
  final List<dynamic> products;
  final int           seed;

  const _InspirationCard({required this.products, required this.seed});

  @override
  State<_InspirationCard> createState() => _InspirationCardState();
}

class _InspirationCardState extends State<_InspirationCard>
    with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _slides;
  int   _currentSlide = 0;
  Timer? _slideTimer;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  static const List<String> _inspirationCats = [
    'Mode', 'Électronique', 'Maison', 'Beauté', 'Automobile', 'Sports',
  ];

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();

    _buildSlides();
    _startAutoSlide();
  }

  void _buildSlides() {
    final rng = Random(widget.seed * 1000);
    final cat = _inspirationCats[widget.seed % _inspirationCats.length];

    // Récupérer les images des produits de cette catégorie
    final catProducts = widget.products
        .where((p) => (p['category'] ?? '').toString().toLowerCase() == cat.toLowerCase())
        .toList();

    // Fallback : prendre n'importe quels produits
    final pool = catProducts.isNotEmpty ? catProducts : widget.products;
    pool.shuffle(rng);

    _slides = pool.take(5).map((p) => {
      'imageUrl': ApiConfig.getImageUrl(p['thumbnail'] ?? p['image'] ?? ''),
      'category': cat,
      'productId': (p['_id'] ?? p['id']).toString(),
    }).toList();

    if (_slides.isEmpty) {
      _slides = [{'imageUrl': '', 'category': cat, 'productId': ''}];
    }
  }

  void _startAutoSlide() {
    _slideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _slides.length <= 1) return;
      _fadeCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _currentSlide = (_currentSlide + 1) % _slides.length);
        _fadeCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) return const SizedBox.shrink();
    final slide    = _slides[_currentSlide];
    final imageUrl = slide['imageUrl'] as String;
    final category = slide['category'] as String;

    return GestureDetector(
      onTap: () => context.go('/home?category=$category'),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [_primary.withValues(alpha: 0.85), _primaryMid.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Image en fondu
            FadeTransition(
              opacity: _fadeAnim,
              child: imageUrl.isNotEmpty
                  ? Image.network(
                imageUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildGradientFallback(category),
              )
                  : _buildGradientFallback(category),
            ),

            // Overlay dégradé
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),

            // Contenu
            Positioned(
              left: 16, right: 16, bottom: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            category.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text('Découvrir la collection',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('VOIR TOUT',
                        style: TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ),
                ],
              ),
            ),

            // Indicateurs slides
            if (_slides.length > 1)
              Positioned(
                top: 12, right: 12,
                child: Row(
                  children: List.generate(_slides.length, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(left: 4),
                    width: _currentSlide == i ? 16 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _currentSlide == i ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientFallback(String category) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary.withValues(alpha: 0.8), _primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.store_rounded, color: Colors.white.withValues(alpha: 0.3), size: 80),
      ),
    );
  }
}

// ─── Notification button ──────────────────────────────────────────────────────
class _NotifButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (_, notif, _) => GestureDetector(
        onTap: () => context.push('/home/notifications'),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6FB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded, color: Color(0xFF0F172A), size: 22),
              Positioned(
                top: -3, right: -3,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Promo banner carousel ────────────────────────────────────────────────────
class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  final PageController _pageController = PageController();
  int    _currentPage = 0;
  Timer? _autoTimer;

  static const List<Map<String, dynamic>> _banners = [
    {
      'title':  'Nouvelle Collection',
      'sub':    'Électronique 2K & 4K',
      'image':  'assets/images/pub2.png',
      'colors': [Color(0xFF1A237E), Color(0xFF3949AB)],
    },
    {
      'title':  'Flash Sale 🔥',
      'sub':    "Jusqu'à -50% aujourd'hui",
      'image':  'assets/images/pub2.png',
      'colors': [Color(0xFFBF360C), Color(0xFFEF6C00)],
    },
  ];

  @override
  void initState() {
    super.initState();
    _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % _banners.length;
      _pageController.animateToPage(next,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 168,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final b = _banners[index];
              return _PromoCard(
                title: b['title'] as String,
                sub:   b['sub']   as String,
                imagePath:      b['image']  as String,
                gradientColors: b['colors'] as List<Color>,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _banners.length,
                (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPage == i ? 18 : 6, height: 6,
              decoration: BoxDecoration(
                color: _currentPage == i ? _primary : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  final String title, sub, imagePath;
  final List<Color> gradientColors;

  const _PromoCard({required this.title, required this.sub, required this.imagePath, required this.gradientColors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: gradientColors[0].withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10, top: -10,
            child: Opacity(
              opacity: 0.35,
              child: Image.asset(imagePath, width: 140, height: 140, fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text('ACHETER',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: gradientColors[0], letterSpacing: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Skeleton box ─────────────────────────────────────────────────────────────
class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double  radius;
  final bool    isFull;

  const _SkeletonBox({
    this.width,
    this.height,
    this.radius = 8,
    this.isFull = false,
  });

  @override
  Widget build(BuildContext context) {
    return _ShimmerWidget(
      child: Container(
        width:  isFull ? double.infinity : width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ─── Shimmer widget ───────────────────────────────────────────────────────────
class _ShimmerWidget extends StatefulWidget {
  final Widget child;
  const _ShimmerWidget({required this.child});

  @override
  State<_ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<_ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1.0, end: 2.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Color(0xFFEEEEEE),
            Color(0xFFF5F5F5),
            Color(0xFFFFFFFF),
            Color(0xFFF5F5F5),
            Color(0xFFEEEEEE),
          ],
          stops: [
            (_anim.value - 0.3).clamp(0.0, 1.0),
            (_anim.value - 0.1).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),
            (_anim.value + 0.1).clamp(0.0, 1.0),
            (_anim.value + 0.3).clamp(0.0, 1.0),
          ],
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}