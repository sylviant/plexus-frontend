import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/providers/category_provider.dart';
import 'package:plexus/core/api_config.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CategoryProvider>(context, listen: false).fetchCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('CATÉGORIES', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18, color: primaryColor)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Consumer<CategoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator(color: primaryColor));

          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.0,
            ),
            itemCount: provider.categories.length,
            itemBuilder: (context, index) {
              final cat = provider.categories[index];
              final String name = cat['name'] ?? 'Inconnu';
              final String imageUrl = ApiConfig.getImageUrl(cat['imageUrl']);

              return GestureDetector(
                onTap: () => context.push('/categories/$name'),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(25),
                        child: Image.network(
                          imageUrl, 
                          fit: BoxFit.cover,
                          errorBuilder: (c,e,s) => Container(color: Colors.grey[100], child: const Icon(Icons.category_outlined, color: Colors.grey)),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20, left: 10, right: 10,
                        child: Text(
                          name.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
