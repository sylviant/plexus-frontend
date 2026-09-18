import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/blockchain/wallet_service.dart';
import 'package:plexus/blockchain/escrow_contract.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:plexus/core/constants/countries.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic>? productData;
  const PaymentScreen({this.productData, super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _hashController    = TextEditingController();
  final _addressController = TextEditingController();
  String? _countryCode; // NOUVEAU — sert au calcul auto des frais de livraison
  bool _isSubmitting       = false;
  String _selectedCrypto   = "USDT";
  String _methode = 'manuel'; // 'manuel' ou 'wallet'

  // ── Blockchain ─────────────────────────────────────────────────────────────
  final WalletService  _walletService  = WalletService();
  final EscrowContract _escrowContract = EscrowContract();
  bool    _walletConnecte = false;
  String? _adresseWallet;
  bool    _isPaying       = false;

  static const String _walletAddress =
      "0x772b9729B0c76cDf4e9295e32664ff01E5757358";

  @override
  void dispose() {
    _hashController.dispose();
    _addressController.dispose();
    _escrowContract.dispose();
    super.dispose();
  }

  void _showSnack(String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Connexion wallet ───────────────────────────────────────────────────────
Future<void> _connecterWallet() async {
  try {
    _walletService.onConnected = () {
      if (mounted) {
        setState(() {
          _walletConnecte = true;
          _adresseWallet  = _walletService.adresseConnectee;
        });
        _showSnack(
          'Wallet connecté ! ${_adresseWallet?.substring(0, 8)}...',
          Colors.green,
          Icons.check_circle,
        );
      }
    };

    final uri = await _walletService.init();
    if (uri == null) return;

    if (kIsWeb) {
      // Web → QR code
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Scanner avec ton wallet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      'Scanne ce QR code avec MetaMask ou Trust Wallet',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  SizedBox(
                      width: 200,
                      height: 200,
                      child: QrImageView(data: uri, size: 200)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Annuler'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } else {
      // Mobile → liste des wallets installés
      final wallets = await _walletService.getWalletsDisponibles(uri);

      if (!mounted) return;

      if (wallets.isEmpty) {
        // Aucun wallet installé
        _showSnack(
          'Aucun wallet compatible installé. Installe MetaMask ou Trust Wallet.',
          Colors.orange,
          Icons.warning,
        );
        return;
      }

      if (wallets.length == 1) {
        // Un seul wallet → ouvre directement
        await _walletService.ouvrirWallet(wallets.first['deeplink']!);
      } else {
        // Plusieurs wallets → laisse choisir
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Choisir ton wallet',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ...wallets.map((wallet) => ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      wallet['icon']!,
                      width: 40, height: 40,
                      errorBuilder: (_, __, ___) => Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.account_balance_wallet,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                  title: Text(wallet['name']!,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 14, color: Colors.grey),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _walletService.ouvrirWallet(wallet['deeplink']!);
                  },
                )),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      }
    }
  } catch (e) {
    _showSnack('Erreur: $e', Colors.red, Icons.error);
  }
}

  // ── Paiement via escrow ────────────────────────────────────────────────────
  Future<void> _payerAvecWallet() async {
    if (!_walletConnecte) {
      _showSnack('Connecte ton wallet d\'abord', Colors.orange, Icons.warning);
      return;
    }
    if (_addressController.text.isEmpty) {
      _showSnack('Entre une adresse de livraison',
          Colors.orange, Icons.location_off);
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final dynamic passedPriceRaw = widget.productData?['price'];
    final double passedPrice = (passedPriceRaw != null)
        ? double.parse(passedPriceRaw.toString()) : 0.0;
    final bool isFromChat    = widget.productData?['orderId'] != null;
    final bool isShippingOnly = widget.productData?['isShippingOnly'] == true;
    final double displayPrice =
        (isFromChat || isShippingOnly) ? passedPrice : cart.totalPrice;

    setState(() => _isPaying = true);
    try {
      final String adresseVendeur = widget.productData?['sellerWallet']
          ?? '0x0000000000000000000000000000000000000000';

      final txHash = await _escrowContract.creerCommande(
        privateKey:     '',
        adresseVendeur: adresseVendeur,
        montantBNB:     displayPrice,
        delaiJours:     7,
      );

      _hashController.text = txHash;
      _showSnack(
        'Paiement envoyé ! Hash: ${txHash.substring(0, 10)}...',
        Colors.green,
        Icons.check_circle,
      );
      await _confirmTransfer();
    } catch (e) {
      _showSnack('Erreur paiement: $e', Colors.red, Icons.error);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  // ── Confirmation manuelle ──────────────────────────────────────────────────
  Future<void> _confirmTransfer() async {
    HapticFeedback.mediumImpact();
    if (_hashController.text.length < 10) {
      _showSnack('Veuillez entrer un Hash (TXID) valide.',
          Colors.orange, Icons.warning_amber_rounded);
      return;
    }
    if (_addressController.text.isEmpty) {
      _showSnack("Veuillez entrer une adresse de livraison.",
          Colors.orange, Icons.location_off_outlined);
      return;
    }
    final bool isFromChatCheck = widget.productData?['orderId'] != null;
    if (!isFromChatCheck && _countryCode == null) {
      _showSnack("Veuillez sélectionner un pays de livraison.",
          Colors.orange, Icons.flag_outlined);
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() => _isSubmitting = true);

    try {
      final bool isFromChat     = widget.productData?['orderId'] != null;
      final bool isShippingOnly = widget.productData?['isShippingOnly'] == true;

      if (isFromChat) {
        final String orderId = widget.productData?['orderId'] ?? '';
        final endpoint = isShippingOnly
            ? '${ApiConfig.baseUrl}/orders/$orderId/approve'
            : '${ApiConfig.baseUrl}/orders/$orderId/status';

        await http.put(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            if (!isShippingOnly) 'status': 'PAID',
            'transactionHash': _hashController.text,
            'cryptoType':      _selectedCrypto,
            'deliveryAddress': _addressController.text,
          }),
        );
        if (mounted) context.go('/profile/orders');
      } else {
        final String? promoCode = widget.productData?['promoCode'] as String?;
        final double promoAmount =
            (widget.productData?['promoAmount'] as num?)?.toDouble() ?? 0.0;

        final orderData = <String, dynamic>{
          'userId':          auth.currentUser!.id,
          'buyerName':       auth.currentUser!.firstName,
          'deliveryAddress': _addressController.text,
          'deliveryCountry': _countryCode, // NOUVEAU — utilisé par computeShippingFee
          'items': cart.items.values.map((item) => {
            'title': item.title, 'price': item.price, 'quantity': item.quantity,
          }).toList(),
          'totalAmount':     cart.totalPrice,
          'sellerId':        widget.productData?['sellerId'] ?? 'Inconnu',
          'transactionHash': _hashController.text,
          'cryptoType':      _selectedCrypto,
          'status':          'PENDING_ADMIN',
        };
        if (promoCode != null) orderData['promoCode']    = promoCode;
        if (promoAmount > 0)   orderData['promoDiscount'] = promoAmount;

        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/orders'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(orderData),
        );
        if (response.statusCode == 201) {
          cart.clear();
          if (mounted) context.go(
            '/cart/confirmation',
            extra: json.decode(response.body),
          );
        }
      }
    } catch (e) {
      _showSnack('Erreur: $e', Colors.red, Icons.error_outline);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);
    final cart = Provider.of<CartProvider>(context);

    final dynamic passedPriceRaw = widget.productData?['price'];
    final double passedPrice = (passedPriceRaw != null)
        ? double.parse(passedPriceRaw.toString()) : 0.0;
    final bool isFromChat     = widget.productData?['orderId'] != null;
    final bool isShippingOnly = widget.productData?['isShippingOnly'] == true;
    final double displayPrice =
        (isFromChat || isShippingOnly) ? passedPrice : cart.totalPrice;

    final String? promoCode = widget.productData?['promoCode'] as String?;
    final double promoDiscount =
        (widget.productData?['promoDiscount'] as num?)?.toDouble() ?? 0.0;
    final double promoAmount =
        (widget.productData?['promoAmount'] as num?)?.toDouble() ?? 0.0;
    final bool hasPromo = promoCode != null && promoAmount > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          isShippingOnly ? 'FRAIS DE LIVRAISON' : 'PAIEMENT SÉCURISÉ',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          children: [

            // ── Montant ──────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(
                  color: primaryColor.withOpacity(0.3),
                  blurRadius: 15, offset: const Offset(0, 8),
                )],
              ),
              child: Column(children: [
                if (isShippingOnly) ...[
                  const Text('FRAIS DE LIVRAISON',
                      style: TextStyle(color: Colors.white60,
                          fontSize: 12, letterSpacing: 1.5)),
                  const SizedBox(height: 6),
                ],
                if (hasPromo && !isFromChat) ...[
                  Text(
                    '\$${cart.rawPrice.toStringAsFixed(2)} $_selectedCrypto',
                    style: const TextStyle(
                      color: Colors.white38, fontSize: 16,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Code $promoCode — −${promoDiscount.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  '\$${displayPrice.toStringAsFixed(2)} $_selectedCrypto',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Adresse livraison ────────────────────────────────────────────
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("ADRESSE DE LIVRAISON",
                  style: TextStyle(fontWeight: FontWeight.bold,
                      color: Colors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                  hintText: "Saisissez votre adresse de réception"),
            ),
            if (!isFromChat) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _countryCode,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: "Pays de livraison",
                ),
                items: kCountries.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _countryCode = value),
              ),
            ],
            const SizedBox(height: 24),

            // ── Sélection méthode de paiement ────────────────────────────────
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("MÉTHODE DE PAIEMENT",
                  style: TextStyle(fontWeight: FontWeight.bold,
                      color: Colors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _methode = 'manuel'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _methode == 'manuel'
                          ? primaryColor : Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _methode == 'manuel'
                            ? primaryColor : Colors.grey[300]!,
                      ),
                    ),
                    child: Column(children: [
                      Icon(Icons.qr_code_rounded,
                          color: _methode == 'manuel'
                              ? Colors.white : Colors.grey, size: 24),
                      const SizedBox(height: 6),
                      Text("Transfert manuel",
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold,
                            color: _methode == 'manuel'
                                ? Colors.white : Colors.grey,
                          )),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _methode = 'wallet'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _methode == 'wallet'
                          ? Colors.green[700] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _methode == 'wallet'
                            ? Colors.green[700]! : Colors.grey[300]!,
                      ),
                    ),
                    child: Column(children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          color: _methode == 'wallet'
                              ? Colors.white : Colors.grey, size: 24),
                      const SizedBox(height: 6),
                      Text("Payer via Escrow",
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold,
                            color: _methode == 'wallet'
                                ? Colors.white : Colors.grey,
                          )),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Contenu selon méthode ────────────────────────────────────────
            if (_methode == 'manuel') ...[

              // ── Crypto ───────────────────────────────────────────────────
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'USDT', label: Text('USDT'),
                      icon: Icon(Icons.currency_bitcoin)),
                  ButtonSegment(value: 'USDC', label: Text('USDC'),
                      icon: Icon(Icons.monetization_on_outlined)),
                ],
                selected: {_selectedCrypto},
                onSelectionChanged: (v) {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedCrypto = v.first);
                },
              ),
              const SizedBox(height: 25),
              _buildWarningBanner(),
              const SizedBox(height: 24),

              // ── QR ───────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.asset(
                    _selectedCrypto == "USDT"
                        ? 'assets/images/usdt.png'
                        : 'assets/images/usdc.png',
                    width: 220, height: 220, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 220, height: 220, color: Colors.grey[100],
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_2_rounded,
                              size: 60, color: Colors.grey),
                          SizedBox(height: 10),
                          Text("Image QR introuvable",
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              const Text("BNB Smart Chain (BEP20)",
                  style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 15),

              // ── Adresse wallet ───────────────────────────────────────────
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Clipboard.setData(const ClipboardData(text: _walletAddress));
                  _showSnack("Adresse copiée !", primaryColor, Icons.copy_rounded);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withOpacity(0.1)),
                  ),
                  child: const Text(_walletAddress,
                      style: TextStyle(
                        color: primaryColor, fontWeight: FontWeight.bold, fontSize: 11,
                      )),
                ),
              ),
              const SizedBox(height: 24),

              // ── Hash TXID ────────────────────────────────────────────────
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("PREUVE DE TRANSFERT (HASH TXID)",
                    style: TextStyle(fontWeight: FontWeight.bold,
                        color: Colors.grey, fontSize: 12)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hashController,
                decoration: const InputDecoration(
                    hintText: "Collez l'ID de transaction"),
              ),
              const SizedBox(height: 24),

              // ── Bouton confirmation manuelle ─────────────────────────────
              SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _confirmTransfer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isShippingOnly
                              ? 'CONFIRMER LES FRAIS DE LIVRAISON'
                              : 'CONFIRMER LE PAIEMENT',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                ),
              ),

            ] else ...[

              // ── Méthode Wallet ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: const Row(children: [
                  Icon(Icons.security, color: Colors.green, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Les fonds sont bloqués dans le smart contract jusqu'à confirmation de livraison. Le vendeur ne peut pas les récupérer avant.",
                      style: TextStyle(fontSize: 11, color: Colors.green),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),

              if (!_walletConnecte)
                SizedBox(
                  width: double.infinity, height: 55,
                  child: OutlinedButton.icon(
                    onPressed: _connecterWallet,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('CONNECTER MON WALLET'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryColor),
                      foregroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                )
              else
                Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _adresseWallet ?? '',
                          style: const TextStyle(fontSize: 11, color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _walletService.deconnecter();
                          setState(() {
                            _walletConnecte = false;
                            _adresseWallet  = null;
                          });
                        },
                        child: const Text('Déconnecter',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity, height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _isPaying ? null : _payerAvecWallet,
                      icon: _isPaying
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: Text(_isPaying
                          ? 'Transaction en cours...'
                          : 'PAYER VIA ESCROW'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                ]),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: Colors.orange, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(
          _selectedCrypto == "USDT"
              ? "N'envoyez que des Tether USD (BEP20). Les autres actifs seront perdus."
              : "N'envoyez que des BNB pegged USD Coin (BEP20). Les autres actifs seront perdus.",
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500),
        )),
      ]),
    );
  }
}