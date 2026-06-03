import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';
import 'package:plexus/presentation/widgets/product_card.dart';

class CategoryProductsScreen extends StatefulWidget {
  final String categoryName;
  const CategoryProductsScreen({required this.categoryName, super.key});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  List<dynamic> _allCategoryProducts = []; 
  List<dynamic> _displayProducts = []; 
  bool _isLoading = true;
  String _selectedSubCategory = "Tout";
  
  final ScrollController _scrollController = ScrollController();
  bool _isHeaderVisible = true;

  final Map<String, List<String>> _subCategoriesMap = {
    'Mode': ['Femme', 'Homme', 'Enfants', 'Accessoires'],
    'Électronique': ['Électricité', 'Quincaillerie', 'Smartphones', 'Informatique'],
    'Maison': ['Mobilier', 'Meubles', 'Décoration', 'Électroménager'],
    'Beauté': ['Maquillage', 'Soins', 'Parfums', 'Hygiène'],
    'Livres': ['Romans', 'Scolaire', 'BD', 'Dév. Personnel'],
    'Sports': ['Fitness', 'Football', 'Outdoor', 'Combat'],
    'Alimentation': ['Épicerie', 'Boissons', 'Frais', 'Surgelés'],
    'Automobile': ['Pièces', 'Accessoires', 'Entretien', 'Pneus'],
    'Jouets': ['Jeux de société', 'Éveil', 'Consoles', 'Figurines'],
    'Jardin': ['Outils', 'Plantes', 'Mobilier de jardin'],
  };

  @override
  void initState() {
    super.initState();
    _fetchCategoryProducts();
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isHeaderVisible) setState(() => _isHeaderVisible = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isHeaderVisible) setState(() => _isHeaderVisible = true);
      }
    });
  }

  Future<void> _fetchCategoryProducts() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/products')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> all = (data['products'] ?? []) as List<dynamic>;
        setState(() {
          final String target = widget.categoryName.toLowerCase().trim();
          _allCategoryProducts = all.where((p) {
            final String productCat = (p['category'] ?? '').toString().toLowerCase().trim();
            return productCat.contains(target) || target.contains(productCat);
          }).toList();
          
          _applyFilters(); 
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _displayProducts = _allCategoryProducts.where((p) {
        if (_selectedSubCategory == "Tout") return true;
        final String sub = (p['subCategory'] ?? '').toString().toLowerCase().trim();
        return sub == _selectedSubCategory.toLowerCase().trim();
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);
    final List<String> subCats = _subCategoriesMap[widget.categoryName] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            pinned: true,
            backgroundColor: primaryColor,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: () => context.pop()),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/categories/${widget.categoryName.toLowerCase()}.png', fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: primaryColor)),
                  Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.8)]))),
                  Positioned(bottom: 25, left: 20, child: Text(widget.categoryName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2))),
                ],
              ),
            ),
          ),
          if (subCats.isNotEmpty)
            SliverToBoxAdapter(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _isHeaderVisible ? 60 : 0,
                child: _isHeaderVisible 
                    ? ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        itemCount: subCats.length + 1,
                        itemBuilder: (context, index) {
                          final label = index == 0 ? "Tout" : subCats[index - 1];
                          return _buildSubCatChip(label);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          _isLoading 
            ? const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator(color: primaryColor))))
            : _displayProducts.isEmpty 
              ? SliverToBoxAdapter(child: Center(child: Padding(padding: const EdgeInsets.all(50), child: Text("Aucun produit disponible"))))
              : SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 15, mainAxisSpacing: 15),
                    delegate: SliverChildBuilderDelegate((context, index) => ProductCard(product: _displayProducts[index]), childCount: _displayProducts.length),
                  ),
                ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildSubCatChip(String label) {
    bool isSel = _selectedSubCategory == label;
    const Color primaryColor = Color(0xFF1A237E);
    return GestureDetector(
      onTap: () { setState(() => _selectedSubCategory = label); _applyFilters(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10, top: 10, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isSel ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSel ? Colors.transparent : Colors.grey[200]!),
        ),
        child: Center(child: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.grey[600], fontSize: 12, fontWeight: isSel ? FontWeight.bold : FontWeight.normal))),
      ),
    );
  }
}
