import 'package:flutter/material.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/favorite_provider.dart';
import 'package:plexus/presentation/widgets/product_card.dart';
import 'package:provider/provider.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    // Charger les favoris au moment où on arrive sur l'écran
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.isAuthenticated && auth.currentUser != null) {
        Provider.of<FavoriteProvider>(context, listen: false)
            .fetchFavorites(auth.currentUser!.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Mes Favoris', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Consumer<FavoriteProvider>(
        builder: (context, favProvider, child) {
          if (favProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (favProvider.favoriteProducts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Votre liste est vide', 
                    style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF283593)),
                    child: const Text("Découvrir des produits", style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              if (auth.currentUser != null) {
                await favProvider.fetchFavorites(auth.currentUser!.id);
              }
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: favProvider.favoriteProducts.length,
              itemBuilder: (context, index) {
                final product = favProvider.favoriteProducts[index];
                if (product == null) return const SizedBox.shrink();
                return ProductCard(product: product);
              },
            ),
          );
        },
      ),
    );
  }
}
