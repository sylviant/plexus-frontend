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
          // On vérifie que productId existe et est bien un objet (grâce au populate du backend)
          final product = item['productId'];
          if (product != null && product is Map) {
            final String id = (product['_id'] ?? product['id']).toString();
            _favoriteIds.add(id);
            _favoriteProducts.add(product);
          }
        }
        debugPrint("✅ Favoris chargés : ${_favoriteProducts.length}");
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
    
    // UI réactive immédiate
    if (_favoriteIds.contains(pIdStr)) {
      _favoriteIds.remove(pIdStr);
      _favoriteProducts.removeWhere((p) => (p['_id'] ?? p['id']).toString() == pIdStr);
    } else {
      _favoriteIds.add(pIdStr);
    }
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/favorites/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId, 'productId': pIdStr}),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // On rafraîchit pour avoir les données complètes du produit
        await fetchFavorites(userId);
      }
    } catch (e) {
      debugPrint('🚨 Erreur toggle: $e');
    }
  }

  bool isFavorite(String? productId) {
    if (productId == null) return false;
    return _favoriteIds.contains(productId.toString());
  }
}
