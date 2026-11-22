import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/blockchain/v2/escrow_session.dart';
import 'package:plexus/blockchain/v2/escrow_v2_errors.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/http_auth.dart' as http;
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
  final _addressController = TextEditingController();
  String? _countryCode;
  bool _isSubmitting = false;

  // Payment is in USDT on BNB Smart Chain, through the V2 escrow contract and the user's own wallet.
  static const String _cryptoType = 'USDT';

  // ── Blockchain ─────────────────────────────────────────────────────────────
  final EscrowSession _session = EscrowSession.instance;
  bool    _walletConnecte = false;
  String? _adresseWallet;
  bool    _isPaying       = false;
  PayStep? _step;

  // One random key per checkout: a retry after a failed payment finds the same order, never a second one.
  String? _idempotencyKey;

  Map<String, dynamic>? get _singleProduct =>
      widget.productData?['singleProduct'] as Map<String, dynamic>?;

  @override
  void initState() {
    super.initState();
    if (_session.isConnected) {
      _walletConnecte = true;
      _adresseWallet = _session.address;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  String _newKey() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
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

  void _onWalletConnected() {
    if (!mounted) return;
    setState(() {
      _walletConnecte = true;
      _adresseWallet  = _session.address;
    });
    final a = _adresseWallet ?? '';
    _showSnack(l10n.walletConnecte(a.length >= 8 ? a.substring(0, 8) : a), Colors.green, Icons.check_circle);
  }

  // ── Connexion wallet ───────────────────────────────────────────────────────
  Future<void> _connecterWallet() async {
    try {
      // On the web, a browser wallet (MetaMask...) is the simplest way when it is installed.
      if (kIsWeb && _session.browserWalletAvailable) {
        await _session.connectBrowserWallet();
        _onWalletConnected();
        return;
      }

      final uri = await _session.startWalletConnect(onConnected: _onWalletConnected);
      if (uri == null || !mounted) return;

      // On a phone, open the wallet app straight away; otherwise (or if none opens) show the QR code.
      var opened = false;
      if (!kIsWeb) {
        try {
          opened = await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
        } catch (_) {
          opened = false;
        }
      }
      if (!opened && mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.scannerAvecTonWallet,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(l10n.scanneCeQrCodeAvec,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  SizedBox(width: 200, height: 200, child: QrImageView(data: uri, size: 200)),
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.annuler)),
                ],
              ),
            ),
          ),
        );
      }
    } on EscrowException catch (e) {
      _showSnack(e.message, Colors.red, Icons.error);
    } catch (e) {
      _showSnack(interpretError(e).message, Colors.red, Icons.error);
    }
  }

  String _stepText(PayStep? s) {
    switch (s) {
      case PayStep.checking:      return 'Checking the price...';
      case PayStep.approving:     return 'Approve USDT in your wallet...';
      case PayStep.creatingOrder: return 'Confirm the payment in your wallet...';
      case PayStep.confirming:    return 'Waiting for the network...';
      default:                    return l10n.transactionEnCours;
    }
  }

  /// Creates the order on the server (the server sets every price) and returns it.
  Future<Map<String, dynamic>> _createOrder(AuthProvider auth, CartProvider cart) async {
    final isSingle = _singleProduct != null;
    final List<Map<String, dynamic>> items = isSingle
        ? [
      {
        'productId': (_singleProduct!['_id'] ?? _singleProduct!['id']).toString(),
        'quantity': 1,
        if (_singleProduct!['variantId'] != null) 'variantId': _singleProduct!['variantId'],
        if (_singleProduct!['selectedColor'] != null) 'color': _singleProduct!['selectedColor'],
        if (_singleProduct!['selectedSize'] != null) 'size': _singleProduct!['selectedSize'],
      }
    ]
        : cart.items.values
        .map((i) => {
      'productId': i.id,
      'quantity': i.quantity,
      if (i.variantId != null) 'variantId': i.variantId,
      if (i.color != null) 'color': i.color,
      if (i.size != null) 'size': i.size,
    })
        .toList();
    final String? promoCode = widget.productData?['promoCode'] as String?;
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/orders'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${auth.token}',
        'Idempotency-Key': _idempotencyKey ??= _newKey(),
      },
      body: json.encode({
        'items': items,
        'deliveryAddress': _addressController.text.trim(),
        'deliveryCountry': _countryCode,
        if (promoCode != null) 'promoCode': promoCode,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      String msg = 'The order could not be created. Please try again.';
      try {
        final body = json.decode(response.body);
        if (body is Map && body['error'] != null) msg = body['error'].toString();
      } catch (_) {}
      throw EscrowException('ORDER_NOT_CREATED', msg);
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  // ── Paiement via escrow V2 ─────────────────────────────────────────────────
  Future<void> _payerAvecWallet() async {
    if (!_walletConnecte || !_session.isConnected) {
      _showSnack(l10n.connecteTonWalletDAbord, Colors.orange, Icons.warning);
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _showSnack(l10n.entreUneAdresseDeLivraison, Colors.orange, Icons.location_off);
      return;
    }
    final bool isFromChat     = widget.productData?['orderId'] != null;
    final bool isShippingOnly = widget.productData?['isShippingOnly'] == true;
    if (!isFromChat && _countryCode == null) {
      _showSnack(l10n.veuillezSelectionnerUnPaysDe, Colors.orange, Icons.flag_outlined);
      return;
    }

    HapticFeedback.mediumImpact();
    final cart = Provider.of<CartProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() { _isPaying = true; _step = PayStep.checking; });
    try {
      if (isShippingOnly) {
        // The seller changed the delivery fee: accepting it pays only the difference, on the existing order.
        final orderId = widget.productData!['orderId'].toString();
        setState(() => _step = PayStep.creatingOrder);
        await _session.service.acceptDeliveryAdjustmentForOrder(EscrowSession.orderRefFor(orderId));
        if (mounted) context.go('/profile/orders');
        return;
      }

      // An order from a chat already exists; a cart or single product creates its order first.
      final Map<String, dynamic>? created = isFromChat ? null : await _createOrder(auth, cart);
      final String orderId = isFromChat ? widget.productData!['orderId'].toString() : created!['_id'].toString();

      final flow = _session.paymentFlow(baseUrl: ApiConfig.baseUrl, authToken: () async => auth.token);
      final outcome = await flow.payOrder(orderId, onStep: (s) {
        if (mounted) setState(() => _step = s);
      });

      final tx = outcome.result.createOrderTx;
      _showSnack(l10n.paiementEnvoyeHash(tx.length >= 10 ? tx.substring(0, 10) : tx), Colors.green, Icons.check_circle);
      if (isFromChat) {
        if (mounted) context.go('/profile/orders');
      } else {
        if (_singleProduct == null) cart.clear();
        if (mounted) context.go('/cart/confirmation', extra: created);
      }
    } on EscrowException catch (e) {
      _showSnack(e.message, Colors.red, Icons.error);
    } catch (e) {
      _showSnack(interpretError(e).message, Colors.red, Icons.error);
    } finally {
      if (mounted) setState(() { _isPaying = false; _step = null; });
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
                  color: primaryColor.withValues(alpha: 0.3),
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
                      color: Colors.white.withValues(alpha: 0.15),
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
                initialValue: _countryCode,
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
                    color: Colors.green.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
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
                        _session.disconnect();
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
                        ? _stepText(_step)
                        : l10n.payerViaEscrow),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
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