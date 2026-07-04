import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // Import indispensable ajouté pour SchedulerPhase
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';

class NotificationProvider with ChangeNotifier {
  List<dynamic> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;

  List<dynamic> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  // Méthode de notification sécurisée pour éviter les crashs pendant le build
  void safeNotify() {
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      Future.microtask(() => notifyListeners());
    }
  }

  Future<void> fetchNotifications(String userId) async {
    _isLoading = true;
    safeNotify();
    
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/notifications/$userId'));
      if (response.statusCode == 200) {
        _notifications = json.decode(response.body);
        _unreadCount = _notifications.where((n) => n['isRead'] == false).length;
      }
    } catch (e) {
      debugPrint("Erreur notifs: $e");
    } finally {
      _isLoading = false;
      safeNotify();
    }
  }

  void addNotification(Map<String, dynamic> notification) {
    _notifications.insert(0, notification);
    _unreadCount++;
    safeNotify();
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      final response = await http.put(Uri.parse('${ApiConfig.baseUrl}/notifications/$notificationId/read'));
      if (response.statusCode == 200) {
        final index = _notifications.indexWhere((n) => n['_id'] == notificationId);
        if (index != -1) {
          _notifications[index]['isRead'] = true;
          _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
          safeNotify();
        }
      }
    } catch (e) {
      debugPrint("Erreur markAsRead: $e");
    }
  }
}
