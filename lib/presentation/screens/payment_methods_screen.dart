import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:plexus/l10n/l10n.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<dynamic> _wallets = [];
  bool _isLoading = true;
  double _balance = 0.0;

  // ─── Palette ────────────────────────────────────────────────────────────────
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
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final wResponse = await http.get(Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/wallets'));
      final bResponse = await http.get(Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/balance'));

      if (wResponse.statusCode == 200 && bResponse.statusCode == 200) {
        setState(() {
          _wallets = json.decode(wResponse.body);
          _balance = (json.decode(bResponse.body)['balance'] as num).toDouble();
        });
      }
    } catch (e) {
      debugPrint('Erreur synchronisation: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showWithdrawDialog() {
    if (_wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Icon(Icons.info_outline, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text(l10n.ajoutezDAbordUnPortefeuille),
          ]),
          backgroundColor: _surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: _divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(l10n.retirerVosGains,
                style: TextStyle(color: _textPri, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 14, color: _textSec),
                const SizedBox(width: 6),
                Text(
                  l10n.soldeDisponible,
                  style: const TextStyle(color: _textSec, fontSize: 13),
                ),
                Text(
                  "\$${_balance.toStringAsFixed(2)}",
                  style: const TextStyle(
                      color: _green, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'DESTINATION'.toUpperCase(),
              style: const TextStyle(
                  color: _textSec, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4),
            ),
            const SizedBox(height: 12),
            ..._wallets.map((w) => _buildWithdrawWalletTile(context, w)),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawWalletTile(BuildContext context, dynamic w) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _requestWithdrawal(w['address']);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  color: _accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w['name'] ?? l10n.wallet,
                      style: const TextStyle(
                          color: _textPri, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(w['address'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _textSec, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: _textSec),
          ],
        ),
      ),
    );
  }

  Future<void> _requestWithdrawal(String walletAddress) async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null || _balance <= 0) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/withdrawals'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': user.id,
          'walletAddress': walletAddress,
          'amount': _balance,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text(l10n.demandeDeRetraitTransmise),
            ]),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        _fetchUserData();
      }
    } catch (e) {
      debugPrint("Erreur retrait: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddWalletDialog() {
    final nameCtrl    = TextEditingController();
    final networkCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.ajouterUnPortefeuille,
                  style: TextStyle(
                      color: _textPri, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(l10n.associezUneAdresseBlockchainA,
                  style: TextStyle(color: _textSec, fontSize: 13, height: 1.4)),
              const SizedBox(height: 24),
              _buildDialogField(controller: nameCtrl,    label: l10n.nomDuPortefeuille, hint: l10n.exMonWalletUsdt),
              const SizedBox(height: 14),
              _buildDialogField(controller: networkCtrl, label: l10n.reseau,              hint: l10n.exTrc20Erc20),
              const SizedBox(height: 14),
              _buildDialogField(controller: addressCtrl, label: l10n.adresseBlockchain,  hint: "0x...",  isMonospace: true),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: _textSec,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: _divider)),
                      ),
                      child: Text(l10n.annuler,
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _addWallet(nameCtrl.text, networkCtrl.text, addressCtrl.text);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(l10n.enregistrer,
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isMonospace = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _textSec, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(
              color: _textPri,
              fontSize: 13,
              fontFamily: isMonospace ? 'monospace' : null),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF3D4155), fontSize: 13),
            filled: true,
            fillColor: _surfaceAlt,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _divider)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _divider)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Future<void> _addWallet(String name, String network, String address) async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null || name.isEmpty || address.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/wallets'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'name': name, 'network': network, 'address': address}),
      );

      if (response.statusCode == 201) {
        _fetchUserData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text(l10n.portefeuilleEnregistre),
            ]),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint("Erreur ajout: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : RefreshIndicator(
              color: _accent,
              backgroundColor: _surface,
              onRefresh: _fetchUserData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Balance Card ─────────────────────────────────────
                    _buildBalanceCard(),
                    const SizedBox(height: 36),

                    // ── Wallets Section ──────────────────────────────────
                    _buildSectionLabel(l10n.adressesDeRetrait),
                    const SizedBox(height: 14),

                    if (_wallets.isEmpty)
                      _buildEmptyWallets()
                    else
                      ..._wallets.map((wallet) =>
                          _buildWalletCard(context, wallet)),

                    const SizedBox(height: 20),

                    // ── Add Wallet Button ────────────────────────────────
                    _buildAddButton(),
                  ],
                ),
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
        l10n.paiementsGains,
        style: TextStyle(
          color: _textPri,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _divider),
      ),
    );
  }

  // ─── Balance Card ─────────────────────────────────────────────────────────────
  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2ADE), Color(0xFF4F6EF7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text(l10n.soldeDisponible2,
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "\$${_balance.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.usdPretARetirer,
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
              ElevatedButton(
                onPressed: _showWithdrawDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _accent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.retirer,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ],
          ),
        ],
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

  // ─── Empty Wallets ────────────────────────────────────────────────────────────
  Widget _buildEmptyWallets() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 36, color: _textSec),
          SizedBox(height: 12),
          Text(l10n.aucunPortefeuilleLie,
              style: TextStyle(color: _textSec, fontSize: 14)),
        ],
      ),
    );
  }

  // ─── Wallet Card ──────────────────────────────────────────────────────────────
  Widget _buildWalletCard(BuildContext context, Map<String, dynamic> wallet) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        color: _accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    wallet['name'] ?? l10n.inconnu,
                    style: const TextStyle(
                        color: _textPri, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _divider),
                ),
                child: Text(
                  wallet['network'] ?? l10n.reseau,
                  style: const TextStyle(
                      color: _textSec,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    wallet['address'] ?? '',
                    style: const TextStyle(
                        color: _textSec,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: wallet['address'] ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(children: [
                          Icon(Icons.copy, color: Colors.white, size: 14),
                          SizedBox(width: 8),
                          Text(l10n.adresseCopiee),
                        ]),
                        backgroundColor: _surface,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(16),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.copy_rounded, size: 14, color: _accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Add Button ───────────────────────────────────────────────────────────────
  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _showAddWalletDialog,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(l10n.ajouterUneAdresse,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: BorderSide(color: _accent.withOpacity(0.4), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}