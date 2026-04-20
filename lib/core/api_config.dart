import 'package:flutter/foundation.dart';

class ApiConfig {
  // MODIFIEZ UNIQUEMENT CETTE LIGNE
  static const String ip = '192.168.1.129';

  static const String baseUrl = 'http://$ip:5000/api';
  static const String socketUrl = 'http://$ip:5000';
  static const String mediaUrl = 'http://$ip:5000/uploads/'; 

  static String getImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    if (rawUrl.startsWith('http')) return rawUrl;

    String path = rawUrl.replaceAll('\\', '/');
    while (path.startsWith('/')) {
      path = path.substring(1);
    }

    // ON UTILISE LA VARIABLE ip DÉFINIE PLUS HAUT
    if (path.contains('uploads/')) {
      return 'http://$ip:5000/$path';
    } else {
      return 'http://$ip:5000/uploads/$path';
    }
  }
}
