import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';

class CategoryProvider with ChangeNotifier {
  List<dynamic> _categories = [];
  bool _isLoading = false;

  List<dynamic> get categories => _categories;
  bool get isLoading => _isLoading;

  Future<void> fetchCategories() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/categories'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // FIX : Gestion flexible du format (Objet ou Liste)
        if (data is List) {
          _categories = data;
        } else if (data is Map && data['categories'] != null) {
          _categories = data['categories'];
        } else {
          _categories = [];
        }
      }
    } catch (e) {
      debugPrint("Erreur chargement catégories: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
