import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';
import 'package:plexus/l10n/l10n.dart';

class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic>? extra;

  const OrderSuccessScreen({
    required this.orderId,
    this.extra,
    super.key,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _order;
  bool _isLoading = true;

  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  // ─── Palette PLEXUS ─────────────────────────────────────────────────────────
  static const Color _navy      = Color(0xFF0D1B4B);
  static const Color _navyMid   = Color(0xFF1A2E6E);
  static const Color _accent    = Color(0xFF4A6CF7);
  static const Color _success   = Color(0xFF10B981);
  static const Color _surface   = Color(0xFFF4F6FF);
  static const Color _card      = Colors.white;
  static const Color _textMain  = Color(0xFF0D1B4B);
  static const Color _textMuted = Color(0xFF8A94B2);
  static const Color _border    = Color(0xFFEBEFF8);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _fadeAnim  = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadOrder();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/orders/${widget.orderId}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _order = json.decode(res.body);
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _conversationId {
    if (widget.extra?['conversationId'] != null &&
        (widget.extra!['conversationId'] as String).isNotEmpty) {
      return widget.extra!['conversationId'] as String;
    }
    if (_order != null) {
      return '${_order!['userId']}_${_order!['sellerId']}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  _buildSuccessIcon(),
                  const SizedBox(height: 28),
                  _buildTitle(),
                  const SizedBox(height: 24),
                  if (_order != null) _buildOrderCard(),
                  const SizedBox(height: 32),
                  _buildPrimaryButton(),
                  const SizedBox(height: 14),
                  _buildSecondaryButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/home'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border, width: 1.2),
              ),
              child: const Icon(Icons.home_outlined, size: 18, color: _textMain),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            l10n.confirmationDeCommande,
            style: TextStyle(
              color: _textMain,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessIcon() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [_success.withValues(alpha: 0.15), _success.withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _success.withValues(alpha: 0.3), width: 2),
          ),
          child: Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _success,
                boxShadow: [
                  BoxShadow(
                    color: _success.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        children: [
          Text(
            l10n.felicitations,
            style: TextStyle(
              color: _textMain,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              l10n.votrePaiementAEteValide,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textMuted,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _success.withValues(alpha: 0.2), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: _success),
                const SizedBox(width: 6),
                Text(
                  l10n.fondsSecurisesParPlexusEscrow,
                  style: TextStyle(
                    color: _success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard() {
    final items = (_order!['items'] as List?) ?? [];
    final double total = (_order!['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final double shippingFee = (_order!['shippingFee'] as num?)?.toDouble() ?? 0.0; // NOUVEAU
    final String status = _order!['status'] ?? '';

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border, width: 1),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3, height: 14,
                  decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.detailsDeLaCommande2,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Articles
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F3FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.shopping_bag_outlined, size: 16, color: _accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item['title'] ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textMain),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '\$${item['price']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _accent),
                  ),
                ],
              ),
            )),
            if (shippingFee > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.livraison, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textMuted)),
                  Text(
                    '\$${shippingFee.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textMuted),
                  ),
                ],
              ),
            ],
            const Divider(color: _border, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.total, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textMain)),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _navy),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 12, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Text(
                    status.replaceAll('_', ' '),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF59E0B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          context.push('/profile/orders/detail', extra: _order ?? {});
        },
        icon: const Icon(Icons.receipt_long_outlined, size: 18),
        label: Text(
          l10n.voirMaCommande,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildSecondaryButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          final convId = _conversationId;
          if (convId.isEmpty) return;
          context.push(
            '/messages/chat/${Uri.encodeComponent(convId)}',
            extra: {
              'otherName': widget.extra?['otherName'] ?? l10n.vendeur,
              'orderId': widget.orderId,
              'conversationId': convId,
            },
          );
        },
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: Text(
          l10n.discuterAvecLeVendeur,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: const BorderSide(color: _accent, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}