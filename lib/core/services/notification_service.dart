import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:plexus/l10n/l10n.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  static Future<void> init() async {
    try {
      // 1. Demander la permission (Indispensable pour Android 13+)
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted notification permission');
      }

      // 2. Configuration locale (Android)
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await _notificationsPlugin.initialize(initializationSettings);

      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        'chat_messages', 
        l10n.messagesDeChat, 
        description: l10n.notificationsPourLesNouveauxMessages,
        importance: Importance.max,
      );

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (e) {
      debugPrint("Notification Init Error: $e");
    }
  }

  // RÉCUPÉRER LE TOKEN RÉEL POUR LE BACKEND
  static Future<String?> getFcmToken() async {
    try {
      if (kIsWeb) return null;
      String? token = await _firebaseMessaging.getToken();
      debugPrint("TOKEN RECUPERE : $token");
      return token;
    } catch (e) {
      debugPrint("FCM Error: $e");
      return null;
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'chat_messages',
      l10n.messagesDeChat,
      importance: Importance.max,
      priority: Priority.high,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(id, title, body, platformChannelSpecifics);
  }
}
