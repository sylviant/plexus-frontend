import 'package:flutter/material.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const Color _bg         = Color(0xFF0F1117);
  static const Color _surface    = Color(0xFF1A1D27);
  static const Color _surfaceAlt = Color(0xFF21253A);
  static const Color _accent     = Color(0xFF4F6EF7);
  static const Color _textPri    = Color(0xFFEBEDF5);
  static const Color _textSec    = Color(0xFF7B8097);
  static const Color _divider    = Color(0xFF252838);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: RefreshIndicator(
        color: _accent,
        backgroundColor: _surface,
        onRefresh: () => Provider.of<NotificationProvider>(context, listen: false)
            .fetchNotifications(auth.currentUser!.id),
        child: Consumer<NotificationProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading && provider.notifications.isEmpty) {
              return _buildLoader();
            }

            if (provider.notifications.isEmpty) {
              return _buildEmpty();
            }

            // CORRECTION TYPE ICI : On force le cast en List<dynamic>
            final grouped = _groupByDate(provider.notifications);
            final keys = grouped.keys.toList();

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: keys.length,
              itemBuilder: (context, i) {
                final label = keys[i];
                final items = grouped[label]!;
                return _buildGroup(context, label, items, provider);
              },
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      title: const Text(
        'Notifications',
        style: TextStyle(color: _textPri, fontSize: 22, fontWeight: FontWeight.w700),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _divider),
      ),
    );
  }

  Widget _buildLoader() => const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2));

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications_outlined, size: 38, color: _textSec),
          const SizedBox(height: 24),
          const Text('Aucune notification', style: TextStyle(color: _textPri, fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildGroup(BuildContext context, String label, List<dynamic> items, NotificationProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(label.toUpperCase(), style: const TextStyle(color: _textSec, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
        ),
        ...items.map((notif) => _buildCard(context, notif, provider)),
      ],
    );
  }

  Widget _buildCard(BuildContext context, dynamic notif, NotificationProvider provider) {
    final bool isRead = notif['isRead'] ?? false;
    final String type = notif['type'] ?? 'system';
    final Color typeColor = _getNotifColor(type);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          if (!isRead) provider.markAsRead(notif['_id'] ?? notif['id']);
          if (notif['conversationId'] != null) {
            context.push('/messages/chat/${notif['conversationId']}', extra: {'otherName': 'Utilisateur'});
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: isRead ? _surface : _surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isRead ? _divider : typeColor.withOpacity(0.25)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(_getNotifIcon(type), color: typeColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notif['title'] ?? '', style: TextStyle(color: _textPri, fontWeight: isRead ? FontWeight.w500 : FontWeight.bold)),
                    Text(notif['message'] ?? '', style: TextStyle(color: _textSec, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, List<dynamic>> _groupByDate(List<dynamic> notifications) {
    final Map<String, List<dynamic>> groups = {};
    for (final notif in notifications) {
      final date = DateTime.parse(notif['createdAt'] ?? DateTime.now().toIso8601String());
      final label = DateFormat('dd MMMM yyyy').format(date);
      groups.putIfAbsent(label, () => []).add(notif);
    }
    return groups;
  }

  IconData _getNotifIcon(String? type) {
    if (type == 'sale') return Icons.shopping_cart;
    if (type == 'shipping_offer') return Icons.local_shipping;
    return Icons.notifications;
  }

  Color _getNotifColor(String? type) {
    if (type == 'sale') return const Color(0xFF34C97B);
    if (type == 'shipping_offer') return const Color(0xFF4F6EF7);
    return const Color(0xFF7B8097);
  }
}
