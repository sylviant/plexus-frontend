import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_product.dart';
import '../api_config.dart';

class ChatMessage {
  final String role; // 'user' ou 'assistant'
  final String content;

  ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
  };
}

class AiChatResponse {
  final String message;
  final List<AiProduct> products;
  final bool hasResults;

  AiChatResponse({
    required this.message,
    required this.products,
    required this.hasResults,
  });
}

class AiChatService {
  static final AiChatService _instance = AiChatService._internal();
  factory AiChatService() => _instance;
  AiChatService._internal();

  final List<ChatMessage> _history = [];

  Future<AiChatResponse> sendMessage(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.serverUrl}/api/ai/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': userMessage,
          'history': _history.map((m) => m.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'];

        // Sauvegarde dans l'historique
        _history.add(ChatMessage(role: 'user', content: userMessage));
        _history.add(ChatMessage(role: 'assistant', content: data['message'] ?? ''));

        // Garde max 10 messages dans l'historique
        if (_history.length > 10) {
          _history.removeRange(0, 2);
        }

        return AiChatResponse(
          message: data['message'] ?? 'Désolé, je n\'ai pas compris.',
          products: (data['products'] as List? ?? [])
              .map((p) => AiProduct.fromJson(p))
              .toList(),
          hasResults: data['has_results'] ?? false,
        );
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      return AiChatResponse(
        message: 'Connexion impossible. Vérifie ta connexion internet.',
        products: [],
        hasResults: false,
      );
    }
  }

  void clearHistory() => _history.clear();
}