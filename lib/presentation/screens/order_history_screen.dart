import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:intl/intl.dart';
import 'package:plexus/l10n/l10n.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<dynamic> _orders = [];
  bool _isLoading = true;
  String? _error;

  // ─── Palette ────────────────────────────────────────────────────────────────
  static const Color _bg         = Color(0xFF0F1117);
  static const Color _surface    = Color(0xFF1A1D27);
  static const Color _surfaceAlt = Color(0xFF21253A);
  static const Color _accent     = Color(0xFF4F6EF7);
  static const Color _textPri    = Color(0xFFEBEDF5);
  static const Color _textSec    = Color(0xFF7B8097);
  static const Color _divider    = Color(0xFF252838);
  static const Color _green      = Color(0xFF34C97B);
  static const Color _orange     = Color(0xFFF5A623);
  static const Color _red        = Color(0xFFEF5350);

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;

    setState(() { _isLoading = true; _error = null; });

    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/orders/user/${user.id}'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() { _orders = json.decode(response.body); _isLoading = false; });
      } else {
        setState(() { _error = l10n.erreurServeur2('${response.statusCode}'); _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = l10n.impossibleDeJoindreLeServeur; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoader()
          : _error != null
              ? _buildErrorView()
              : _orders.isEmpty
                  ? _buildEmptyView()
                  : RefreshIndicator(
                      color: _accent,
                      backgroundColor: _surface,
                      onRefresh: _fetchOrders,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) =>
                            _buildOrderCard(_orders[index]),
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
      titleSpacing: 20,
      title: Text(
        l10n.mesAchats,
        style: TextStyle(
          color: _textPri,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _divider),
              ),
              child: const Icon(Icons.refresh_rounded, size: 18, color: _textPri),
            ),
            onPressed: _fetchOrders,
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _divider),
      ),
    );
  }

  // ─── Loader ──────────────────────────────────────────────────────────────────
  Widget _buildLoader() => const Center(
        child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
      );

  // ─── Order Card ───────────────────────────────────────────────────────────────
  Widget _buildOrderCard(dynamic order) {
    final String status   = order['status'] ?? 'PENDING';
    final DateTime date   = DateTime.parse(order['createdAt'] ?? DateTime.now().toIso8601String());
    final double total    = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final int itemCount   = (order['items'] as List?)?.length ?? 0;
    final String orderId  = (order['_id'] ?? '').toString();
    final String shortId  = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;

    final statusInfo = _getStatusInfo(status);

    return GestureDetector(
      onTap: () => context.push('/profile/orders/detail', extra: order),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              // ── Header ───────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.receipt_long_outlined,
                            size: 18, color: _textSec),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#$shortId',
                            style: const TextStyle(
                              color: _textPri,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${DateFormat.yMMMd().format(date)} · ${DateFormat.jm().format(date)}',
                            style: const TextStyle(color: _textSec, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusInfo.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: statusInfo.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusInfo.label,
                          style: TextStyle(
                            color: statusInfo.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Divider ───────────────────────────────────────────────────
              Container(
                height: 1,
                color: _divider,
                margin: const EdgeInsets.symmetric(vertical: 14),
              ),

              // ── Footer ────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 14, color: _textSec),
                      const SizedBox(width: 5),
                      Text(
                        l10n.favoritesCount(itemCount),
                        style: const TextStyle(color: _textSec, fontSize: 13),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 12, color: _textSec),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Error View ───────────────────────────────────────────────────────────────
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _red.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 36, color: _red),
            ),
            const SizedBox(height: 20),
            Text(l10n.connexionImpossible,
                style: TextStyle(color: _textPri, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textSec, fontSize: 13, height: 1.4)),
            const SizedBox(height: 28),
            SizedBox(
              width: 140,
              height: 44,
              child: ElevatedButton(
                onPressed: _fetchOrders,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.reessayer, style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Empty View ───────────────────────────────────────────────────────────────
  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: _divider, width: 1.5),
              ),
              child: const Icon(Icons.shopping_bag_outlined, size: 38, color: _textSec),
            ),
            const SizedBox(height: 24),
            Text(l10n.aucunAchat,
                style: TextStyle(color: _textPri, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              l10n.vosCommandesPasseesApparaitrontIci,
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSec, fontSize: 14, height: 1.5),
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
      case 'Terminé':
        return _StatusInfo(label: l10n.livre,       color: _green);
      case 'SHIPPED':
        return _StatusInfo(label: l10n.enTransit,  color: _accent);
      case 'CANCELLED':
        return _StatusInfo(label: l10n.annule,      color: _red);
      default:
        return _StatusInfo(label: l10n.enAttente,  color: _orange);
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  const _StatusInfo({required this.label, required this.color});
}