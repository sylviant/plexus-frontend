import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/models/user_type.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:plexus/presentation/widgets/category_list.dart';
import 'package:plexus/presentation/widgets/product_card.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';

class HomeScreen extends StatefulWidget {
  final String? initialCategory;
  const HomeScreen({this.initialCategory, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _allProducts = [];
  List<dynamic> _filteredProducts = [];
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();
  late String _selectedCategory;

  final ScrollController _scrollController = ScrollController();
  bool _isVisible = true;

  // ─── Palette ─────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Tout';
    _fetchProducts();

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
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Backend logic (unchanged) ───────────────────────────────────────────

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
          setState(() {
            _allProducts = data['products'] as List<dynamic>;
            _isLoading = false;
          });
          _applyFilters();
        }
      } else {
        if (mounted) setState(() { _error = "Erreur serveur"; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = "Connexion impossible"; _isLoading = false; });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    final selectedCat = _selectedCategory.toLowerCase().trim();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch =
            (p['title'] ?? '').toString().toLowerCase().contains(query);
        final matchesCategory = selectedCat == 'tout' ||
            (p['category'] ?? '').toString().toLowerCase() == selectedCat;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bienvenue sur',
                        style: TextStyle(
                            color: _textSub,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: const [
                          Text(
                            'PLEXUS',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _primary,
                              letterSpacing: 3,
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'MARKET',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w300,
                              color: _primaryMid,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  _NotifButton(),
                ],
              ),
            ),

            // ── Search bar (hide on scroll down) ──────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              height: _isVisible ? 64 : 0,
              curve: Curves.easeInOut,
              color: Colors.white,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _isVisible ? 1 : 0,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border, width: 1.5),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => _applyFilters(),
                      style: const TextStyle(
                          color: _textMain,
                          fontWeight: FontWeight.w500,
                          fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Rechercher un article...',
                        hintStyle: TextStyle(
                            color: _textSub.withOpacity(0.5),
                            fontSize: 14),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: _textSub, size: 20),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.tune_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Category list (hide on scroll down) ────────────────────
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

            // Thin shadow separator
            Container(
              height: 1,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: _primary.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),

            // ── Body ───────────────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _error != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _fetchProducts,
                          color: _primary,
                          child: CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              // Promo banners
                              const SliverToBoxAdapter(
                                  child: PromoBannerCarousel()),

                              // Section title
                              _buildSectionTitle('Pour vous'),

                              // Products grid
                              if (_filteredProducts.isEmpty)
                                SliverToBoxAdapter(
                                  child: _buildEmptySearch(),
                                )
                              else
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      childAspectRatio: 0.72,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) => ProductCard(
                                          product: _filteredProducts[i]),
                                      childCount: _filteredProducts.length,
                                    ),
                                  ),
                                ),

                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 10)),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Consumer<UserProvider>(
        builder: (context, user, child) {
          if (user.userType != UserType.seller)
            return const SizedBox.shrink();
          return Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primary, _primaryMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _primary.withOpacity(0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: FloatingActionButton.extended(
              onPressed: () => context.push('/profile/add-product'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text(
                'VENDRE',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _primary.withOpacity(0.08), blurRadius: 20)
              ],
            ),
            child: const Icon(Icons.wifi_off_rounded,
                size: 36, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 20),
          Text(_error!,
              style: const TextStyle(
                  color: _textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          const SizedBox(height: 8),
          const Text('Vérifiez votre connexion internet.',
              style: TextStyle(color: _textSub, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchProducts,
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 16),
            label: const Text('Réessayer',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
          const Icon(Icons.search_off_rounded,
              size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 16),
          Text(
            'Aucun résultat pour\n"${_searchController.text}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _textMain, fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 6),
          const Text('Essayez un autre terme ou une autre catégorie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSub, fontSize: 12)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _textMain,
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            Text(
              'Voir tout',
              style: TextStyle(
                color: _primaryMid,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Notification button ──────────────────────────────────────────────────────

class _NotifButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
            const Icon(Icons.notifications_none_rounded,
                color: Color(0xFF0F172A), size: 22),
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
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
  int _currentPage = 0;

static const List<Map<String, dynamic>> _banners = [
  {
    'title': 'Nouvelle Collection',
    'sub': 'Électronique 2K & 4K',
    'image': 'assets/images/pub1.png',
    'colors': [Color(0xFF1A237E), Color(0xFF3949AB)],
  },
  {
    'title': 'Flash Sale 🔥',
    'sub': "Jusqu'à -50% aujourd'hui",
    'image': 'assets/images/pub1.png',
    'colors': [Color(0xFFBF360C), Color(0xFFEF6C00)],
  },
];

  @override
  void dispose() {
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
                sub: b['sub'] as String,
                imagePath: b['image'] as String,
                gradientColors: b['colors'] as List<Color>,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _banners.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPage == i ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _currentPage == i
                    ? const Color(0xFF1A237E)
                    : const Color(0xFFE2E8F0),
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
  final String title;
  final String sub;
  final String imagePath;
  final List<Color> gradientColors;

  const _PromoCard({
    required this.title,
    required this.sub,
    required this.imagePath,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background image (remplace l'icône)
          Positioned(
            right: -10,
            top: -10,
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                imagePath,
                width: 140,
                height: 140,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'ACHETER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: gradientColors[0],
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}