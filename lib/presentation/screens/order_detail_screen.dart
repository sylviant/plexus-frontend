import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:go_router/go_router.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({required this.order, super.key});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late String _status;
  bool _isUpdating = false;

  // ─── Palette ────────────────────────────────────────────────────────────
  static const Color _bg         = Color(0xFF0F1117);
  static const Color _surface    = Color(0xFF1A1D27);
  static const Color _surfaceAlt = Color(0xFF21253A);
  static const Color _accent     = Color(0xFF4F6EF7);
  static const Color _textPri    = Color(0xFFEBEDF5);
  static const Color _textSec    = Color(0xFF7B8097);
  static const Color _divider    = Color(0xFF252838);
  static const Color _green      = Color(0xFF34C97B);

  @override
  void initState() {
    super.initState();
    _status = widget.order['status']?.toString() ?? "PENDING_SHIPPING";
  }

  Future<void> _confirmReceipt() async {
    setState(() => _isUpdating = true);
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/orders/${widget.order['_id']}/receive'),
      );

      if (response.statusCode == 200) {
        setState(() => _status = "DELIVERED");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text("Merci ! Le vendeur a été payé."),
              ],
            ),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint("Erreur réception: $e");
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(
        widget.order['createdAt'] ?? DateTime.now().toIso8601String());
    final List items = widget.order['items'] ?? [];
    final currentUser = Provider.of<AuthProvider>(context).currentUser;

    final bool isBuyer  = currentUser?.id == widget.order['userId'];
    final bool isSeller = currentUser?.id == widget.order['sellerId'];

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Statut Banner ──────────────────────────────────────────────
            _buildStatusBanner(date),
            const SizedBox(height: 24),

            // ── Chat Button ────────────────────────────────────────────────
            _buildChatButton(context, isSeller, items),
            const SizedBox(height: 32),

            // ── SECTION ADRESSE DE LIVRAISON (NOUVEAU) ─────────────────────
            _buildSectionLabel('Adresse de livraison'),
            const SizedBox(height: 12),
            _buildAddressCard(widget.order['deliveryAddress'] ?? 'Aucune adresse renseignée'),
            const SizedBox(height: 32),

            // ── Articles Section ───────────────────────────────────────────
            _buildSectionLabel('Articles commandés'),
            const SizedBox(height: 12),
            _buildItemsList(items),

            const SizedBox(height: 32),

            // ── Total Row ──────────────────────────────────────────────────
            _buildTotalRow(items),
            const SizedBox(height: 32),

            // ── Confirm Receipt ────────────────────────────────────────────
            if (isBuyer && _status == 'SHIPPED') ...[
              Container(
                height: 1,
                color: _divider,
                margin: const EdgeInsets.only(bottom: 28),
              ),
              _buildConfirmButton(),
            ],
          ],
        ),
      ),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      leading: IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _divider),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 16, color: _textPri),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Détails de la commande',
        style: TextStyle(
          color: _textPri,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _divider),
      ),
    );
  }

  // ─── Status Banner ───────────────────────────────────────────────────────────
  Widget _buildStatusBanner(DateTime date) {
    final statusInfo = _getStatusInfo(_status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusInfo.color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusInfo.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusInfo.icon, color: statusInfo.color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusInfo.label,
                        style: TextStyle(
                          color: statusInfo.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 12, color: _textSec),
                    const SizedBox(width: 5),
                    Text(
                      DateFormat('dd MMMM yyyy').format(date),
                      style: const TextStyle(color: _textSec, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Chat Button ─────────────────────────────────────────────────────────────
  Widget _buildChatButton(
      BuildContext context, bool isSeller, List items) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () {
          context.push(
              '/messages/chat/${widget.order['userId']}_${widget.order['sellerId']}',
              extra: {
                'otherName':
                    isSeller ? widget.order['buyerName'] : 'Vendeur',
                'productTitle':
                    items.isNotEmpty ? items[0]['title'] : 'Commande',
                'orderId': widget.order['_id'],
              });
        },
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: Text(
          isSeller ? "Discuter avec l'acheteur" : "Contacter le vendeur",
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.2),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ─── Section Label ────────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: _textSec,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  // ─── Address Card (NOUVEAU) ──────────────────────────────────────────────────
  Widget _buildAddressCard(String address) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, color: _accent, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              address,
              style: const TextStyle(
                color: _textPri,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Items List ───────────────────────────────────────────────────────────────
  Widget _buildItemsList(List items) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final isLast = i == items.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.inventory_2_outlined,
                          size: 18, color: _textSec),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item['title'] ?? 'Produit',
                        style: const TextStyle(
                          color: _textPri,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '\$${item['price']}',
                      style: const TextStyle(
                        color: _textPri,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Container(height: 1, color: _divider, margin: const EdgeInsets.symmetric(horizontal: 18)),
            ],
          );
        }),
      ),
    );
  }

  // ─── Total Row ────────────────────────────────────────────────────────────────
  Widget _buildTotalRow(List items) {
    final double total = items.fold(0.0, (sum, item) {
      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
      return sum + price;
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total',
            style: TextStyle(
                color: _textSec, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Text(
            '\$${total.toStringAsFixed(2)}',
            style: const TextStyle(
              color: _accent,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Confirm Receipt Button ───────────────────────────────────────────────────
  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isUpdating ? null : _confirmReceipt,
        style: ElevatedButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _green.withOpacity(0.4),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: _isUpdating
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_outlined, size: 20),
                  SizedBox(width: 10),
                  Text(
                    "J'ai bien reçu le colis",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2),
                  ),
                ],
              ),
      ),
    );
  }

  // ─── Status Helper ────────────────────────────────────────────────────────────
  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'DELIVERED':
        return _StatusInfo(
            label: 'LIVRÉ',
            color: _green,
            icon: Icons.check_circle_outline_rounded);
      case 'SHIPPED':
        return _StatusInfo(
            label: 'EN TRANSIT',
            color: const Color(0xFF4F6EF7),
            icon: Icons.local_shipping_outlined);
      case 'PENDING_SHIPPING':
        return _StatusInfo(
            label: 'EN ATTENTE',
            color: const Color(0xFFF5A623),
            icon: Icons.hourglass_top_rounded);
      case 'CANCELLED':
        return _StatusInfo(
            label: 'ANNULÉ',
            color: const Color(0xFFEF5350),
            icon: Icons.cancel_outlined);
      default:
        return _StatusInfo(
            label: status,
            color: _textSec,
            icon: Icons.info_outline_rounded);
    }
  }
}

// ─── Helper Class ─────────────────────────────────────────────────────────────
class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo(
      {required this.label, required this.color, required this.icon});
}
