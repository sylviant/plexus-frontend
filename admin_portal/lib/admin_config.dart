class AdminConfig {
  // URL NORTHFLANK SANS SLASH FINAL
  static const String serverUrl = 'https://site--plexus-backend--pgpb968tdsqh.code.run';
  static const String baseUrl = '$serverUrl/api';

  static String getImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    if (rawUrl.startsWith('http')) return rawUrl;
    
    String path = rawUrl.replaceAll('\\\\', '/').replaceAll('\\', '/');
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    
    return '$serverUrl/$path';
  }
}
