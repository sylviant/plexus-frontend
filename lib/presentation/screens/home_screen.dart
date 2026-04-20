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

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Tout';
    _fetchProducts();
    
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isVisible) setState(() => _isVisible = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isVisible) setState(() => _isVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/products')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() { _allProducts = data['products'] as List<dynamic>; _isLoading = false; });
        _applyFilters();
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
        final matchesSearch = (p['title'] ?? '').toString().toLowerCase().contains(query);
        final matchesCategory = selectedCat == 'tout' || (p['category'] ?? '').toString().toLowerCase() == selectedCat;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Bienvenue sur", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      const Text("PLEXUS MARKET", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: primaryColor, letterSpacing: 1)),
                    ],
                  ),
                  const Spacer(),
                  _buildIconButton(Icons.notifications_none_rounded, () => context.push('/home/notifications'), hasBadge: true),
                ],
              ),
            ),

            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: _isVisible ? 80 : 0,
              curve: Curves.easeInOut,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _isVisible ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 5))],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => _applyFilters(),
                      decoration: InputDecoration(
                        hintText: "Rechercher un article...",
                        prefixIcon: const Icon(Icons.search_rounded, color: primaryColor),
                        suffixIcon: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: _isVisible ? 110 : 0,
              curve: Curves.easeInOut,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: _isVisible ? 1 : 0,
                child: CategoryList(
                  selectedCategory: _selectedCategory,
                  onCategorySelected: (cat) { setState(() => _selectedCategory = cat); _applyFilters(); },
                ),
              ),
            ),

            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: primaryColor))
                : RefreshIndicator(
                    onRefresh: _fetchProducts,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        const SliverToBoxAdapter(child: PromoBannerCarousel()),
                        _buildSectionTitle("Pour vous"),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => ProductCard(product: _filteredProducts[i]),
                              childCount: _filteredProducts.length, // CORRIGÉ : childCount au lieu de child_count
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: Consumer<UserProvider>(
        builder: (context, user, child) {
          if (user.userType != UserType.seller) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => context.push('/profile/add-product'),
            backgroundColor: primaryColor,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text("VENDRE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          );
        },
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, {bool hasBadge = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[100]!)),
        child: Icon(icon, color: Colors.black87),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const Spacer(),
            const Text("Voir tout", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class PromoBannerCarousel extends StatelessWidget {
  const PromoBannerCarousel({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: PageView(
        children: const [
          PromoCard(title: "Nouvelle Collection", sub: "Électronique 2K & 4K", color: Color(0xFF1A237E)),
          PromoCard(title: "Flash Sale", sub: "Jusqu'à -50% aujourd'hui", color: Color(0xFFFBC02D)),
        ],
      ),
    );
  }
}

class PromoCard extends StatelessWidget {
  final String title, sub; final Color color;
  const PromoCard({required this.title, required this.sub, required this.color, super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(25),
        image: const DecorationImage(image: NetworkImage("https://www.transparenttextures.com/patterns/cubes.png"), opacity: 0.1, repeat: ImageRepeat.repeat),
      ),
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {}, 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0)),
              child: const Text("ACHETER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
