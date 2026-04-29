import 'package:flutter/foundation.dart';

class ApiConfig {
  // MODIFIEZ UNIQUEMENT CETTE LIGNE
  static const String ip = '192.168.1.129'; 

  static const String baseUrl = 'http://$ip:5000/api';
  static const String socketUrl = 'http://$ip:5000';
  static const String mediaUrl = 'http://$ip:5000/uploads/'; 

  // FONCTION DE RÉPARATION D'URLS (Fixe les erreurs d'IP en base de données)
  static String getImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';

    String path = rawUrl;

    // 1. Si l'URL contient une IP (ex: stockée en dur dans la DB)
    // On remplace n'importe quelle IP locale par l'IP actuelle du fichier config
    final ipRegex = RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');
    if (path.startsWith('http') && ipRegex.hasMatch(path)) {
      path = path.replaceFirst(ipRegex, ip);
      return path;
    }

    // 2. Si c'est un chemin relatif (ex: uploads/products/...)
    if (!path.startsWith('http')) {
      path = path.replaceAll('\\', '/');
      while (path.startsWith('/')) {
        path = path.substring(1);
      }
      
      if (path.contains('uploads/')) {
        return 'http://$ip:5000/$path';
      } else {
        return 'http://$ip:5000/uploads/$path';
      }
    }

    return path;
  }

  static String handleNetworkError(dynamic error) {
    if (error.toString().contains('SocketException')) {
      return "🌐 Problème de connexion. Vérifiez votre Wi-Fi.";
    } else if (error.toString().contains('Timeout')) {
      return "⏳ Le serveur met trop de temps à répondre.";
    }
    return "❌ Une erreur inattendue est survenue.";
  }
}
