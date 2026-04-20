import 'package:flutter/material.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: RefreshIndicator(
        onRefresh: () => Provider.of<NotificationProvider>(context, listen: false).fetchNotifications(auth.currentUser!.id),
        child: Consumer<NotificationProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading && provider.notifications.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.notifications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_none, size: 100, color: Colors.grey[200]),
                    const SizedBox(height: 20),
                    const Text('Aucune alerte pour le moment', 
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: provider.notifications.length,
              itemBuilder: (context, index) {
                final notif = provider.notifications[index];
                
                DateTime date;
                try {
                  date = DateTime.parse(notif['createdAt'] ?? DateTime.now().toIso8601String());
                } catch (e) {
                  date = DateTime.now();
                }

                final bool isRead = notif['isRead'] ?? false;
                final String notifId = (notif['_id'] ?? notif['id'] ?? "").toString();
                final String? conversationId = notif['conversationId'];
                final String? type = notif['type'];

                return Container(
                  color: isRead ? Colors.transparent : const Color(0xFFE3F2FD).withOpacity(0.3),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundColor: _getNotifColor(type).withOpacity(0.1),
                      child: Icon(_getNotifIcon(type), color: _getNotifColor(type), size: 24),
                    ),
                    title: Text(
                      notif['title'] ?? 'Alerte PLEXUS',
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          notif['message'] ?? '',
                          style: TextStyle(color: isRead ? Colors.grey : Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('dd/MM à HH:mm').format(date),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    onTap: () {
                      if (!isRead && notifId.isNotEmpty) {
                        provider.markAsRead(notifId);
                      }

                      // LOGIQUE DE REDIRECTION CORRIGÉE POUR LE ROUTER
                      if (conversationId != null && conversationId.isNotEmpty) {
                        // Utilisation du chemin complet défini dans router.dart
                        context.push('/messages/chat/$conversationId', extra: {
                          'otherName': 'Utilisateur',
                        });
                      } else if (type == 'sale' || type == 'shipping_offer') {
                        context.go('/messages');
                      }
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  IconData _getNotifIcon(String? type) {
    switch (type) {
      case 'sale': return Icons.shopping_cart;
      case 'shipping_offer': return Icons.local_shipping;
      case 'payment': return Icons.account_balance_wallet;
      case 'system': return Icons.info_outline;
      default: return Icons.notifications;
    }
  }

  Color _getNotifColor(String? type) {
    switch (type) {
      case 'sale': return Colors.green;
      case 'shipping_offer': return Colors.blue;
      case 'payment': return Colors.orange;
      case 'system': return Colors.indigo;
      default: return Colors.blueGrey;
    }
  }
}
