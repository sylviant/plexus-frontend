import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';

class FavoriteProvider with ChangeNotifier {
  final Set<String> _favoriteIds = {}; 
  List<dynamic> _favoriteProducts = [];
  bool _isLoading = false;

  Set<String> get favoriteIds => _favoriteIds;
  List<dynamic> get favoriteProducts => _favoriteProducts;
  bool get isLoading => _isLoading;

  Future<void> fetchFavorites(String userId) async {
    if (userId.isEmpty) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/favorites/$userId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        
        _favoriteIds.clear();
        _favoriteProducts.clear();

        for (var item in data) {
          final product = item['productId'];
          if (product != null) {
            _favoriteProducts.add(product);
            final String id = (product['_id'] ?? product['id']).toString();
            _favoriteIds.add(id);
          }
        }
      }
    } catch (e) {
      debugPrint('🚨 Erreur récupération favoris: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(String userId, String productId) async {
    final String pIdStr = productId.toString();
    
    // Optimisme UI : On change immédiatement l'icône
    if (_favoriteIds.contains(pIdStr)) {
      _favoriteIds.remove(pIdStr);
      _favoriteProducts.removeWhere((p) => (p['_id'] ?? p['id']).toString() == pIdStr);
    } else {
      _favoriteIds.add(pIdStr);
      // On attendra le fetch pour ajouter le produit complet à la liste
    }
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/favorites/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId, 'productId': pIdStr}),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchFavorites(userId); // Rechargement propre depuis le serveur
      }
    } catch (e) {
      debugPrint('🚨 Erreur toggle favoris: $e');
    }
  }

  bool isFavorite(String productId) => _favoriteIds.contains(productId.toString());
}
