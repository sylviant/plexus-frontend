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
import 'package:plexus/l10n/l10n.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic>? productData;
  const PaymentScreen({this.productData, super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _hashController    = TextEditingController(); // rempli automatiquement par l'escrow
  final _addressController = TextEditingController();
  String? _countryCode;
  bool _isSubmitting = false;

  // Le paiement se fait uniquement en BNB via le smart contract escrow.
  static const String _cryptoType = 'BNB';

  // ── Blockchain ─────────────────────────────────────────────────────────────
  final WalletService  _walletService  = WalletService();
  final EscrowContract _escrowContract = EscrowContract();
  bool    _walletConnecte = false;
  String? _adresseWallet;
  bool    _isPaying       = false;

  Map<String, dynamic>? get _singleProduct =>
      widget.productData?['singleProduct'] as Map<String, dynamic>?;

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
            l10n.walletConnecte('${_adresseWallet?.substring(0, 8)}'),
            Colors.green,
            Icons.check_circle,
          );
        }
      };

      final uri = await _walletService.init();
      if (uri == null) return;

      if (kIsWeb) {
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
                    Text(l10n.scannerAvecTonWallet,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                        l10n.scanneCeQrCodeAvec,
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
                      child: Text(l10n.annuler),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      } else {
        final wallets = await _walletService.getWalletsDisponibles(uri);

        if (!mounted) return;

        if (wallets.isEmpty) {
          _showSnack(
            l10n.aucunWalletCompatibleInstalleInstalle,
            Colors.orange,
            Icons.warning,
          );
          return;
        }

        if (wallets.length == 1) {
          await _walletService.ouvrirWallet(wallets.first['deeplink']!);
        } else {
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
                  Text(l10n.choisirTonWallet,
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
      _showSnack(l10n.erreur3('$e'), Colors.red, Icons.error);
    }
  }

  // ── Paiement via escrow ────────────────────────────────────────────────────
  Future<void> _payerAvecWallet() async {
    if (!_walletConnecte) {
      _showSnack(l10n.connecteTonWalletDAbord, Colors.orange, Icons.warning);
      return;
    }
    if (_addressController.text.isEmpty) {
      _showSnack(l10n.entreUneAdresseDeLivraison,
          Colors.orange, Icons.location_off);
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final dynamic passedPriceRaw = widget.productData?['price'];
    final double passedPrice = (passedPriceRaw != null)
        ? double.parse(passedPriceRaw.toString()) : 0.0;
    final bool isFromChat    = widget.productData?['orderId'] != null;
    final bool isShippingOnly = widget.productData?['isShippingOnly'] == true;
    final double displayPrice = (isFromChat || isShippingOnly)
        ? passedPrice
        : (_singleProduct != null)
        ? ((_singleProduct!['price'] as num?)?.toDouble() ?? 0.0)
        : cart.totalPrice;

    setState(() => _isPaying = true);
    try {
      final String adresseVendeur = widget.productData?['sellerWallet']
          ?? _singleProduct?['sellerWallet']
          ?? '0x0000000000000000000000000000000000000000';

      final txHash = await _escrowContract.creerCommande(
        privateKey:     '',
        adresseVendeur: adresseVendeur,
        montantBNB:     displayPrice,
        delaiJours:     7,
      );

      _hashController.text = txHash;
      _showSnack(
        l10n.paiementEnvoyeHash('${txHash.substring(0, 10)}'),
        Colors.green,
        Icons.check_circle,
      );
      await _confirmTransfer();
    } catch (e) {
      _showSnack(l10n.erreurPaiement('$e'), Colors.red, Icons.error);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  // ── Finalisation de la commande après transaction escrow ──────────────────
  Future<void> _confirmTransfer() async {
    HapticFeedback.mediumImpact();
    if (_hashController.text.length < 10) {
      _showSnack(l10n.transactionIntrouvableReessaieLePaiement,
          Colors.orange, Icons.warning_amber_rounded);
      return;
    }
    if (_addressController.text.isEmpty) {
      _showSnack(l10n.veuillezEntrerUneAdresseDe,
          Colors.orange, Icons.location_off_outlined);
      return;
    }
    final bool isFromChatCheck = widget.productData?['orderId'] != null;
    if (!isFromChatCheck && _countryCode == null) {
      _showSnack(l10n.veuillezSelectionnerUnPaysDe,
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
            'cryptoType':      _cryptoType,
            'deliveryAddress': _addressController.text,
          }),
        );
        if (mounted) context.go('/profile/orders');
      } else {
        final String? promoCode = widget.productData?['promoCode'] as String?;
        final double promoAmount =
            (widget.productData?['promoAmount'] as num?)?.toDouble() ?? 0.0;

        final bool isSingle = _singleProduct != null;
        final double singlePrice =
            (_singleProduct?['price'] as num?)?.toDouble() ?? 0.0;

        final orderData = <String, dynamic>{
          'userId':          auth.currentUser!.id,
          'buyerName':       auth.currentUser!.firstName,
          'deliveryAddress': _addressController.text,
          'deliveryCountry': _countryCode,
          'items': isSingle
              ? [{
            'title':    _singleProduct!['title'],
            'price':    singlePrice,
            'quantity': 1,
          }]
              : cart.items.values.map((item) => {
            'title': item.title, 'price': item.price, 'quantity': item.quantity,
          }).toList(),
          'totalAmount': isSingle ? singlePrice : cart.totalPrice,
          'sellerId': isSingle
              ? (_singleProduct!['sellerId'] ?? 'Inconnu')
              : (widget.productData?['sellerId'] ?? 'Inconnu'),
          'sellerWallet': isSingle ? (_singleProduct!['sellerWallet'] ?? '') : '',
          'transactionHash': _hashController.text,
          'cryptoType':      _cryptoType,
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
          if (!isSingle) cart.clear();
          if (mounted) context.go(
            '/cart/confirmation',
            extra: json.decode(response.body),
          );
        }
      }
    } catch (e) {
      _showSnack(l10n.erreur3('$e'), Colors.red, Icons.error_outline);
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
    final double displayPrice = (isFromChat || isShippingOnly)
        ? passedPrice
        : (_singleProduct != null)
        ? ((_singleProduct!['price'] as num?)?.toDouble() ?? 0.0)
        : cart.totalPrice;

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
          isShippingOnly ? l10n.fraisDeLivraison : l10n.paiementSecurise,
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
                  Text(l10n.fraisDeLivraison,
                      style: TextStyle(color: Colors.white60,
                          fontSize: 12, letterSpacing: 1.5)),
                  const SizedBox(height: 6),
                ],
                if (hasPromo && !isFromChat) ...[
                  Text(
                    '\$${cart.rawPrice.toStringAsFixed(2)} $_cryptoType',
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
                      l10n.code('$promoCode', '${promoDiscount.toStringAsFixed(0)}'),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  '\$${displayPrice.toStringAsFixed(2)} $_cryptoType',
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l10n.adresseDeLivraison2,
                  style: TextStyle(fontWeight: FontWeight.bold,
                      color: Colors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                  hintText: l10n.saisissezVotreAdresseDeReception),
            ),
            if (!isFromChat) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _countryCode,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: l10n.paysDeLivraison,
                ),
                items: kCountries.entries
                    .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(trCountry(e.key)),
                ))
                    .toList(),
                onChanged: (value) => setState(() => _countryCode = value),
              ),
            ],
            const SizedBox(height: 28),

            // ── Paiement sécurisé via Escrow ─────────────────────────────────
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("PAIEMENT",
                  style: TextStyle(fontWeight: FontWeight.bold,
                      color: Colors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(children: [
                Icon(Icons.security, color: Colors.green, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.lesFondsSontBloquesDans,
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
                  label: Text(l10n.connecterMonWallet),
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
                      child: Text(l10n.deconnecter,
                          style: TextStyle(fontSize: 11)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton.icon(
                    onPressed: (_isPaying || _isSubmitting) ? null : _payerAvecWallet,
                    icon: (_isPaying || _isSubmitting)
                        ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                    label: Text((_isPaying || _isSubmitting)
                        ? l10n.transactionEnCours
                        : l10n.payerViaEscrow),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ]),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}