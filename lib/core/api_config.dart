import 'package:flutter/foundation.dart';

class ApiConfig {
  // --- CONFIGURATION SERVEUR NORTHFLANK ---
  // REMPLACEZ CETTE URL PAR VOTRE URL RÉELLE NORTHFLANK
  static const String serverUrl = 'site--plexus-backend--pgpb968tdsqh.code.run';

  static const String baseUrl = '$serverUrl/api';
  static const String socketUrl = serverUrl;
  static const String mediaUrl = '$serverUrl/uploads/';

  // FONCTION DE RÉPARATION D'URLS (Indispensable pour l'affichage des images)
  static String getImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    String path = rawUrl;

    final ipRegex = RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?');
    if (path.startsWith('http') && ipRegex.hasMatch(path)) {
      try {
        Uri uri = Uri.parse(path);
        path = uri.path; 
      } catch (e) {
        return path;
      }
    }

    if (!path.startsWith('http')) {
      path = path.replaceAll('\\', '/');
      while (path.startsWith('/')) { path = path.substring(1); }
      
      if (path.contains('uploads/')) {
        return '$serverUrl/$path';
      } else {
        return '$serverUrl/uploads/$path';
      }
    }

    return path;
  }

  static String handleNetworkError(dynamic error) {
    if (error.toString().contains('SocketException')) {
      return "🌐 Impossible de joindre le serveur Northflank.";
    } else if (error.toString().contains('Timeout')) {
      return "⏳ Le serveur est trop lent à répondre.";
    }
    return "❌ Erreur : $error";
  }
}
