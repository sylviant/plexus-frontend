import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:plexus/core/http_auth.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/services/escrow_pay_service.dart';
import 'package:plexus/l10n/l10n.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailScreen({required this.order, super.key});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late String _status;
  bool _isUpdating = false;

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
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _confirmReceipt() async {
    setState(() => _isUpdating = true);
    try {
      final String orderId = widget.order['_id'].toString();
      final String? escrowId = widget.order['escrowId']?.toString();
      final bool hasEscrow =
          escrowId != null && escrowId != 'null' && escrowId.isNotEmpty;

      // ── Commande payée via escrow : confirmation ON-CHAIN via la page Thirdweb ──
      if (hasEscrow) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await EscrowPayService.open(
          orderId: orderId,
          token: auth.token!,
          action: EscrowAction.confirm,
        );
        // Le backend vérifie la transaction sur la blockchain puis passe la commande en DELIVERED.
        final updated = await EscrowPayService.waitFor(
          orderId,
              (o) => o['status'] == 'DELIVERED',
          shouldStop: () => !mounted,
        );
        if (updated != null && mounted) {
          setState(() => _status = "DELIVERED");
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text(l10n.merciLeVendeurAEte),
            ]),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
        }
        return;
      }

      // ── Ancienne commande sans escrow : confirmation côté backend uniquement ──
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/orders/$orderId/receive'),
      );

      if (response.statusCode == 200) {
        setState(() => _status = "DELIVERED");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text(l10n.merciLeVendeurAEte),
            ]),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
        }
      }
    } catch (e) {
      debugPrint("Erreur réception: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(widget.order['createdAt'] ?? DateTime.now().toIso8601String());
    final List   items  = widget.order['items'] ?? [];
    final currentUser   = Provider.of<AuthProvider>(context).currentUser;
    final bool isBuyer  = currentUser?.id == widget.order['userId'];
    final bool isSeller = currentUser?.id == widget.order['sellerId'];

    // ── Données promo depuis la commande ──────────────────────────────────
    final String? promoCode     = widget.order['promoCode'] as String?;
    final double  promoDiscount = (widget.order['promoDiscount'] as num?)?.toDouble() ?? 0.0;
    final bool    hasPromo      = promoCode != null && promoDiscount > 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(date),
            const SizedBox(height: 24),
            _buildChatButton(context, isSeller, items),
            const SizedBox(height: 32),

            // ── Adresse livraison ─────────────────────────────────────────
            _buildSectionLabel(l10n.adresseDeLivraison),
            const SizedBox(height: 12),
            _buildAddressCard(widget.order['deliveryAddress'] ?? l10n.aucuneAdresseRenseignee),
            const SizedBox(height: 32),

            // ── Articles ──────────────────────────────────────────────────
            _buildSectionLabel(l10n.articlesCommandes),
            const SizedBox(height: 12),
            _buildItemsList(items),
            const SizedBox(height: 32),

            // ── Récapitulatif prix ────────────────────────────────────────
            _buildSectionLabel(l10n.recapitulatif),
            const SizedBox(height: 12),
            _buildPriceSummary(items, hasPromo, promoCode, promoDiscount),
            const SizedBox(height: 32),

            // ── Confirmation réception ────────────────────────────────────
            if (isBuyer && _status == 'SHIPPED') ...[
              Container(height: 1, color: _divider, margin: const EdgeInsets.only(bottom: 28)),
              _buildConfirmButton(),
            ],
          ],
        ),
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _bg, elevation: 0, centerTitle: false, titleSpacing: 4,
      leading: IconButton(
        icon: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _divider)),
          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _textPri),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(l10n.detailsDeLaCommande, style: TextStyle(color: _textPri, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: _divider)),
    );
  }

  // ─── Status Banner ────────────────────────────────────────────────────────
  Widget _buildStatusBanner(DateTime date) {
    final si = _getStatusInfo(_status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: si.color.withOpacity(0.3))),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: si.color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(si.icon, color: si.color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: si.color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(si.label, style: TextStyle(color: si.color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 12, color: _textSec),
            const SizedBox(width: 5),
            Text(DateFormat.yMMMMd().format(date), style: const TextStyle(color: _textSec, fontSize: 13)),
          ]),
        ])),
      ]),
    );
  }

  // ─── Chat Button ──────────────────────────────────────────────────────────
  Widget _buildChatButton(BuildContext context, bool isSeller, List items) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton.icon(
        onPressed: () => context.push(
          '/messages/chat/${widget.order['userId']}_${widget.order['sellerId']}',
          extra: {
            'otherName':    isSeller ? widget.order['buyerName'] : l10n.vendeur,
            'productTitle': items.isNotEmpty ? items[0]['title'] : l10n.commande,
            'orderId':      widget.order['_id'],
          },
        ),
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: Text(isSeller ? l10n.discuterAvecLAcheteur : l10n.contacterLeVendeur,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2)),
        style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    );
  }

  // ─── Section Label ────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) => Text(label.toUpperCase(),
      style: const TextStyle(color: _textSec, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4));

  // ─── Address Card ─────────────────────────────────────────────────────────
  Widget _buildAddressCard(String address) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _divider)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.location_on_outlined, color: _accent, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Text(address, style: const TextStyle(color: _textPri, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  // ─── Items List ───────────────────────────────────────────────────────────
  Widget _buildItemsList(List items) {
    return Container(
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _divider)),
      child: Column(children: List.generate(items.length, (i) {
        final item  = items[i];
        final isLast = i == items.length - 1;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: _surfaceAlt, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.inventory_2_outlined, size: 18, color: _textSec),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(item['title'] ?? l10n.produit, style: const TextStyle(color: _textPri, fontSize: 14, fontWeight: FontWeight.w500))),
              Text('\$${item['price']}', style: const TextStyle(color: _textPri, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (!isLast) Container(height: 1, color: _divider, margin: const EdgeInsets.symmetric(horizontal: 18)),
        ]);
      })),
    );
  }

  // ─── NOUVEAU : Récapitulatif avec promo ───────────────────────────────────
  Widget _buildPriceSummary(List items, bool hasPromo, String? promoCode, double promoDiscount) {
    final double rawTotal = items.fold(0.0, (sum, item) {
      return sum + (double.tryParse(item['price']?.toString() ?? '0') ?? 0);
    });
    final double finalTotal = hasPromo ? rawTotal - promoDiscount : rawTotal;

    return Container(
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _divider)),
      child: Column(children: [
        // Sous-total articles
        _priceRow(l10n.sousTotalArticles, '\$${rawTotal.toStringAsFixed(2)}', _textSec, false),
        Container(height: 1, color: _divider, margin: const EdgeInsets.symmetric(horizontal: 18)),

        // Réduction promo (affichée seulement si applicable)
        if (hasPromo) ...[
          _priceRow(
            l10n.reduction2('$promoCode'),
            '−\$${promoDiscount.toStringAsFixed(2)}',
            const Color(0xFF34C97B),
            false,
            icon: Icons.local_offer_rounded,
          ),
          Container(height: 1, color: _divider, margin: const EdgeInsets.symmetric(horizontal: 18)),
        ],

        // Total final
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l10n.totalPaye, style: TextStyle(color: _textSec, fontSize: 14, fontWeight: FontWeight.w500)),
            Text('\$${finalTotal.toStringAsFixed(2)}', style: const TextStyle(color: _accent, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _priceRow(String label, String value, Color valueColor, bool isBold, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 14, color: valueColor), const SizedBox(width: 8)],
        Expanded(child: Text(label, style: TextStyle(color: _textSec, fontSize: 13, fontWeight: isBold ? FontWeight.w700 : FontWeight.w400))),
        Text(value, style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ─── Confirm Button ───────────────────────────────────────────────────────
  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton(
        onPressed: _isUpdating ? null : _confirmReceipt,
        style: ElevatedButton.styleFrom(
          backgroundColor: _green, foregroundColor: Colors.white,
          disabledBackgroundColor: _green.withOpacity(0.4),
          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isUpdating
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.verified_outlined, size: 20),
          SizedBox(width: 10),
          Text(l10n.jAiBienRecuLe, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        ]),
      ),
    );
  }

  // ─── Status Info ──────────────────────────────────────────────────────────
  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'DELIVERED':      return _StatusInfo(label: l10n.livre,      color: _green,                      icon: Icons.check_circle_outline_rounded);
      case 'SHIPPED':        return _StatusInfo(label: l10n.enTransit,  color: const Color(0xFF4F6EF7),     icon: Icons.local_shipping_outlined);
      case 'PENDING_ADMIN':  return _StatusInfo(label: l10n.verification,color: const Color(0xFF9B8EF7),     icon: Icons.admin_panel_settings_outlined);
      case 'PENDING_SHIPPING': return _StatusInfo(label: l10n.enAttente, color: const Color(0xFFF5A623),   icon: Icons.hourglass_top_rounded);
      case 'CANCELLED':      return _StatusInfo(label: l10n.annule,      color: const Color(0xFFEF5350),     icon: Icons.cancel_outlined);
      default:               return _StatusInfo(label: status,        color: _textSec,                    icon: Icons.info_outline_rounded);
    }
  }
}

class _StatusInfo {
  final String label;
  final Color  color;
  final IconData icon;
  const _StatusInfo({required this.label, required this.color, required this.icon});
}