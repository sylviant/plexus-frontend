import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart'; 
import 'package:flutter/scheduler.dart'; // Import indispensable ajouté
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/services/notification_service.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:plexus/l10n/l10n.dart';

class SocketProvider with ChangeNotifier {
  IO.Socket? _socket;
  final _messageController = StreamController<ChatMessage>.broadcast();
  String? _currentActiveRoom; 
  bool _isConnected = false;
  
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  bool get isConnected => _isConnected;

  final Map<String, Map<String, dynamic>> _conversations = {};
  Map<String, Map<String, dynamic>> get conversations => _conversations;

  Stream<ChatMessage> get messageStream => _messageController.stream;

  // Méthode de notification sécurisée
  void safeNotify() {
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      Future.microtask(() => notifyListeners());
    }
  }

  Future<void> loadConversations(String userId) async {
    try {
      print("📡 Messagerie: Chargement de l'historique...");
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/messages/history/$userId'))
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _conversations.clear();
        for (var conv in data) {
          final String roomId = conv['conversationId'];
          final lastMsg = conv['lastMessage'];
          
          _conversations[roomId] = {
            'message': ChatMessage(
              text: lastMsg['text'],
              user: ChatUser(id: lastMsg['senderId'], firstName: lastMsg['senderName']),
              createdAt: DateTime.parse(lastMsg['createdAt']),
            ),
            'name': conv['otherUserName'] ?? l10n.utilisateur,
          };
        }
        safeNotify();
        print("✅ ${data.length} conversations récupérées.");
      }
    } catch (e) {
      print("⚠️ Impossible de charger l'historique: $e");
    }
  }

  void connect(String userId, NotificationProvider notifProvider) {
    if (_socket != null && _socket!.connected) return;

    try {
      print("🔌 Connexion au serveur de messages: ${ApiConfig.socketUrl}");
      _socket = IO.io(ApiConfig.socketUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });

      _socket!.connect();

      _socket!.onConnect((_) {
        print('✅ Connecté au Socket (ID: $userId)');
        _isConnected = true;
        _socket!.emit('joinUserRoom', userId);
        loadConversations(userId); 
        safeNotify();
      });

      _socket!.onConnectError((data) {
        print("❌ Erreur technique Socket: $data");
        _isConnected = false;
        safeNotify();
      });

      _socket!.onDisconnect((_) {
        _isConnected = false;
        safeNotify();
      });

      _socket!.on('newMessage', (data) {
        try {
          final message = ChatMessage.fromJson(data);
          final String roomId = data['conversationId'] ?? 'default';
          final String senderName = data['senderName'] ?? l10n.utilisateur;

          _conversations[roomId] = {'message': message, 'name': senderName};

          if (_currentActiveRoom != roomId) {
            _unreadCount++;
            NotificationService.showNotification(
              id: roomId.hashCode,
              title: l10n.nouveauMessageDe(senderName),
              body: trChatText(message.text),
            );
          }
          _messageController.add(message);
          safeNotify();
        } catch(e) { print("Erreur message: $e"); }
      });

      _socket!.on('newNotification', (data) {
        notifProvider.addNotification(data);
        NotificationService.showNotification(
          id: (data['_id'] ?? data['id']).hashCode,
          title: (data['title'] ?? l10n.alerte).toString(),
          body: (data['message'] ?? "").toString(),
        );
      });

    } catch (e) { print("🚨 Exception Socket: $e"); }
  }

  void enterChat(String roomId) {
    _currentActiveRoom = roomId;
    _unreadCount = 0; 
    _socket?.emit('joinRoom', roomId);
    safeNotify();
  }

  void leaveChat() {
    _currentActiveRoom = null;
    safeNotify();
  }

  void sendMessage(ChatMessage message, String roomId, String senderName) {
    if (_socket != null && _socket!.connected) {
      Map<String, dynamic> data = message.toJson();
      data['conversationId'] = roomId;
      data['senderName'] = senderName; 
      _socket!.emit('sendMessage', data);
      _conversations[roomId] = {'message': message, 'name': l10n.moi};
      safeNotify();
    }
  }

  @override
  void dispose() {
    _socket?.dispose();
    _messageController.close();
    super.dispose();
  }
}
