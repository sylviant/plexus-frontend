import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/presentation/widgets/product_card.dart';
import 'package:plexus/l10n/l10n.dart';

class SellerProfileScreen extends StatefulWidget {
  final String sellerId;
  const SellerProfileScreen({required this.sellerId, super.key});

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _seller;
  List<dynamic> _products = [];
  bool _isLoading = true;
  bool _hasError = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // ── Stats : articles vendus, note moyenne, parrainages ────────────────────
  int    _soldCount     = 0;
  double _avgRating     = 0;
  int    _ratingCount   = 0;
  int    _referralCount = 0;

  // ─── Palette (alignée sur seller_hub_screen.dart) ────────────────────────────
  static const Color _navy = Color(0xFF0D1B4B);
  static const Color _navyMid = Color(0xFF1A2E6E);
  static const Color _accent = Color(0xFF4A6CF7);
  static const Color _surface = Color(0xFFF4F6FF);
  static const Color _card = Colors.white;
  static const Color _textPrimary = Color(0xFF0D1B4B);
  static const Color _textMuted = Color(0xFF8A94B2);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _fetchSellerData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ─── Drapeau depuis code pays ISO 2 lettres (ex: "CM" → 🇨🇲) ──────────────
  static String _countryFlag(String code) {
    if (code.length != 2) return '';
    return code.toUpperCase().runes
        .map((r) => String.fromCharCode(r - 0x41 + 0x1F1E6))
        .join();
  }

  String? get _sellerCountry {
    for (final p in _products) {
      final c = p['sellerCountry'];
      if (c is String && c.length == 2) return c.toUpperCase();
    }
    return null;
  }

  Future<void> _fetchSellerData() async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse('${ApiConfig.baseUrl}/users/${widget.sellerId}')),
        http.get(Uri.parse('${ApiConfig.baseUrl}/products/seller/${widget.sellerId}')),
        http.get(Uri.parse('${ApiConfig.baseUrl}/sellers/${widget.sellerId}/stats')),
      ]);
      final resU = results[0];
      final resP = results[1];
      final resS = results[2];

      if (mounted) {
        setState(() {
          if (resU.statusCode == 200) {
            _seller = json.decode(resU.body);
          } else {
            _hasError = true;
          }
          if (resP.statusCode == 200) {
            _products = json.decode(resP.body)['products'] ?? [];
          }
          if (resS.statusCode == 200) {
            final stats = json.decode(resS.body);
            _soldCount     = (stats['soldCount']     as num?)?.toInt()    ?? 0;
            _avgRating     = (stats['avgRating']     as num?)?.toDouble() ?? 0;
            _ratingCount   = (stats['ratingCount']   as num?)?.toInt()    ?? 0;
            _referralCount = (stats['referralCount'] as num?)?.toInt()    ?? 0;
          }
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final bool isOwnProfile = auth.currentUser?.id == widget.sellerId;

    return Scaffold(
      backgroundColor: _surface,
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : _hasError || _seller == null
          ? _buildErrorState()
          : RefreshIndicator(
        color: _accent,
        onRefresh: _fetchSellerData,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(child: _buildHero(isOwnProfile)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _buildProductsHeader(),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 56),
                sliver: _products.isEmpty
                    ? SliverToBoxAdapter(child: _buildEmptyState())
                    : SliverGrid(
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, i) => ProductCard(product: _products[i], standalone: true),
                    childCount: _products.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: _navy,
      elevation: 0,
      pinned: true,
      expandedHeight: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 17, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(bool isOwnProfile) {
    final String name = _seller!['name'] ?? l10n.vendeur;
    final String? profileImage = _seller!['profileImage'];
    final bool isApproved = _seller!['isApproved'] == true;
    final String memberSince = _memberSinceLabel(_seller!['createdAt']);
    final String? countryCode = _sellerCountry;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navy, _navyMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.25), width: 2),
            ),
            child: ClipOval(
              child: profileImage != null && profileImage.isNotEmpty
                  ? Image.network(
                ApiConfig.getImageUrl(profileImage),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildAvatarFallback(name),
              )
                  : _buildAvatarFallback(name),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              if (isApproved) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded, color: Color(0xFF4A6CF7), size: 20),
              ],
              if (countryCode != null) ...[
                const SizedBox(width: 8),
                Text(_countryFlag(countryCode), style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 3),
                Text(
                  countryCode,
                  style: const TextStyle(
                    color: Color(0xFF4A6CF7),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isApproved ? l10n.vendeurVerifie('$memberSince') : memberSince,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          // Wrap plutôt que Row : évite un débordement si les 4 badges
          // ne tiennent pas sur une seule ligne (petit écran, nom long...).
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildStatChip(
                Icons.inventory_2_outlined,
                '${_products.length}',
                _products.length > 1 ? 'articles' : 'article',
              ),
              _buildStatChip(
                Icons.local_shipping_outlined,
                '$_soldCount',
                _soldCount > 1 ? 'vendus' : 'vendu',
              ),
              _buildRatingChip(),
              _buildStatChip(
                Icons.group_add_outlined,
                '$_referralCount',
                _referralCount > 1 ? 'parrainages' : 'parrainage',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Container(
      color: _accent,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 30),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withOpacity(0.8)),
          const SizedBox(width: 7),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontWeight: FontWeight.w500,
                  fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRatingChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFBBF24)),
          const SizedBox(width: 5),
          Text(
            _ratingCount > 0 ? _avgRating.toStringAsFixed(1) : '—',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
          ),
          if (_ratingCount > 0) ...[
            const SizedBox(width: 4),
            Text(
              '($_ratingCount)',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontWeight: FontWeight.w500,
                  fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductsHeader() {
    return Text(
      l10n.articlesEnVente,
      style: TextStyle(
        color: _textMuted,
        fontWeight: FontWeight.w800,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEBEFF8)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_2_outlined,
                size: 40, color: _textMuted),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.aucunArticlePublie,
            style: TextStyle(
                color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.ceVendeurNAPas,
            textAlign: TextAlign.center,
            style: TextStyle(color: _textMuted, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_outlined, size: 48, color: _textMuted),
            const SizedBox(height: 16),
            Text(
              l10n.impossibleDeChargerCeProfil,
              style: TextStyle(
                  color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _fetchSellerData,
              child: Text(l10n.reessayer,
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  String _memberSinceLabel(String? createdAt) {
    if (createdAt == null) return l10n.membrePlexus;
    try {
      final date = DateTime.parse(createdAt);
      return l10n.membreDepuis('${date.year}');
    } catch (_) {
      return l10n.membrePlexus;
    }
  }
}