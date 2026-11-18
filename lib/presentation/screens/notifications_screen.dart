import 'package:material_ui/material_ui.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/l10n/l10n.dart';

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
            final grouped = _groupByDate(provider.notifications.cast<Map<String, dynamic>>().toList());
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.notifications,
            style: TextStyle(
              color: _textPri,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _divider),
      ),
    );
  }

  Widget _buildLoader() {
    return const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2));
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: _divider, width: 1.5),
              ),
              child: const Icon(Icons.notifications_outlined, size: 38, color: _textSec),
            ),
            const SizedBox(height: 24),
            Text(l10n.aucuneNotification,
                style: TextStyle(color: _textPri, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              l10n.vosAlertesPlexusApparaitrontIci,
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSec, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(
    BuildContext context,
    String label,
    List<Map<String, dynamic>> items,
    NotificationProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _textSec, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4,
            ),
          ),
        ),
        ...items.map((notif) => _buildCard(context, notif, provider)),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context,
    Map<String, dynamic> notif,
    NotificationProvider provider,
  ) {
    DateTime date;
    try {
      date = DateTime.parse(notif['createdAt'] ?? DateTime.now().toIso8601String());
    } catch (_) {
      date = DateTime.now();
    }

    final bool isRead            = notif['isRead'] ?? false;
    final String notifId         = (notif['_id'] ?? notif['id'] ?? '').toString();
    final String? conversationId = notif['conversationId'];
    final String? orderId        = (notif['orderId'] ?? notif['order_id'] ?? '').toString().isEmpty
                                      ? null
                                      : (notif['orderId'] ?? notif['order_id']).toString();
    final String? type           = notif['type'];
    final String? senderName     = notif['senderName'] ?? notif['otherName'];
    final String? productTitle   = notif['productTitle'] ?? notif['product'];

    final Color typeColor   = _getNotifColor(type);
    final IconData typeIcon = _getNotifIcon(type);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (!isRead && notifId.isNotEmpty) {
              provider.markAsRead(notifId);
            }

            // ✅ NOUVEAU : Redirection vers la page de succès pour l'acheteur
            if (type == 'order_validated' && orderId != null && orderId.isNotEmpty) {
              context.push('/order-success/$orderId', extra: {
                'conversationId': conversationId ?? '',
                'otherName': senderName ?? l10n.vendeur,
              });
              return;
            }

            if (conversationId != null && conversationId.isNotEmpty) {
              context.push(
                '/messages/chat/${Uri.encodeComponent(conversationId)}',
                extra: {
                  'otherName': senderName ?? l10n.utilisateur,
                  'orderId': orderId ?? '',
                  'productTitle': productTitle ?? '',
                  'conversationId': conversationId,
                },
              );
            } else if (type == 'sale' || type == 'shipping_offer') {
              context.go('/messages');
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isRead ? _surface : _surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isRead ? _divider : typeColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notif['title'] ?? l10n.alertePlexus,
                                style: TextStyle(
                                  color: _textPri,
                                  fontSize: 14.5,
                                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (!isRead)
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          notif['message'] ?? '',
                          style: TextStyle(
                            color: isRead ? _textSec : _textPri.withValues(alpha: 0.75),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 12, color: _textSec),
                            const SizedBox(width: 4),
                            Text(
                              l10n.dateAtTime(DateFormat.Md().format(date), DateFormat.jm().format(date)),
                              style: const TextStyle(fontSize: 11, color: _textSec, letterSpacing: 0.2),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> notifications) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final notif in notifications) {
      DateTime date;
      try {
        date = DateTime.parse(notif['createdAt'] ?? DateTime.now().toIso8601String());
      } catch (_) { date = DateTime.now(); }
      final dateOnly = DateTime(date.year, date.month, date.day);
      String label;
      if (dateOnly == today) {
        label = l10n.aujourdHui;
      } else if (dateOnly == yesterday) {
        label = l10n.hier;
      } else {
        label = DateFormat.yMMMMd().format(date);
      }
      groups.putIfAbsent(label, () => []).add(notif);
    }
    return groups;
  }

  IconData _getNotifIcon(String? type) {
    switch (type) {
      case 'sale':            return Icons.shopping_cart;
      case 'shipping_offer':  return Icons.local_shipping;
      case 'payment':         return Icons.account_balance_wallet;
      case 'system':          return Icons.info_outline;
      case 'order_validated': return Icons.verified_rounded;  // ✅ NOUVEAU
      default:                return Icons.notifications;
    }
  }

  Color _getNotifColor(String? type) {
    switch (type) {
      case 'sale':            return Colors.green;
      case 'shipping_offer':  return Colors.orange;
      case 'payment':         return Colors.blue;
      case 'system':          return Colors.indigo;
      case 'order_validated': return const Color(0xFF10B981); // ✅ NOUVEAU — vert émeraude
      default:                return _accent;
    }
  }
}