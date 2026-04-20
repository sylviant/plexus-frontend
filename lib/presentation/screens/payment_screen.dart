import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic>? productData; 

  const PaymentScreen({this.productData, super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _hashController = TextEditingController();
  final _addressController = TextEditingController(); 
  bool _isSubmitting = false;
  
  // SÉLECTION DE LA CRYPTO
  String _selectedCrypto = "USDT";

  // ADRESSES DE PAIEMENT
  static const String _usdtWallet = "0x772b9729B0c76cDf4e9295e32664ff01E5757358"; // Adresse USDT
  static const String _usdcWallet = "0x772b9729B0c76cDf4e9295e32664ff01E5757358"; // Adresse USDC (Identique ici, changez si besoin)

  String get _activeWallet => _selectedCrypto == "USDT" ? _usdtWallet : _usdcWallet;

  @override
  void dispose() {
    _hashController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _confirmTransfer() async {
    if (_hashController.text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un Hash (TXID) valide.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    
    setState(() => _isSubmitting = true);

    try {
      final bool isFromChat = widget.productData?['orderId'] != null;
      final bool isShippingPayment = widget.productData?['isShippingOnly'] ?? false;

      if (isFromChat || isShippingPayment) {
        final String orderId = widget.productData?['orderId'] ?? '';
        await http.put(
          Uri.parse('${ApiConfig.baseUrl}/orders/$orderId/status'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'status': 'PAID',
            'transactionHash': _hashController.text,
            'cryptoType': _selectedCrypto,
          }),
        );
        if (mounted) context.go('/profile/orders');
      } else {
        if (_addressController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veuillez entrer une adresse de livraison.")));
          setState(() => _isSubmitting = false);
          return;
        }

        final orderData = {
          'userId': auth.currentUser!.id,
          'buyerName': auth.currentUser!.firstName,
          'deliveryAddress': _addressController.text,
          'items': cart.items.values.map((item) => {'title': item.title, 'price': item.price, 'quantity': item.quantity}).toList(),
          'totalAmount': cart.totalPrice,
          'sellerId': widget.productData?['sellerId'] ?? 'Inconnu',
          'platformWallet': _activeWallet,
          'transactionHash': _hashController.text,
          'cryptoType': _selectedCrypto,
          'status': 'PENDING_SHIPPING',
        };

        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/orders'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(orderData),
        );

        if (response.statusCode == 201) {
          cart.clear();
          if (mounted) context.go('/cart/confirmation', extra: json.decode(response.body));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final dynamic passedPriceRaw = widget.productData?['price'];
    final double passedPrice = (passedPriceRaw != null) ? double.parse(passedPriceRaw.toString()) : 0.0;
    final bool isFromChat = widget.productData?['orderId'] != null;
    final bool isShippingPayment = widget.productData?['isShippingOnly'] ?? false;
    final double displayPrice = (isFromChat || isShippingPayment) ? passedPrice : cart.totalPrice;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Paiement Sécurisé'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AFFICHAGE DU MONTANT
            Container(
              width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF283593), borderRadius: BorderRadius.circular(20)),
              child: Text('\$${displayPrice.toStringAsFixed(2)} $_selectedCrypto', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 30),

            // SÉLECTEUR DE CRYPTO
            const Text('Choisissez votre moyen de paiement', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'USDT', label: Text('USDT'), icon: Icon(Icons.currency_bitcoin)),
                  ButtonSegment(value: 'USDC', label: Text('USDC'), icon: Icon(Icons.monetization_on_outlined)),
                ],
                selected: {_selectedCrypto},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _selectedCrypto = newSelection.first);
                },
              ),
            ),
            const SizedBox(height: 30),

            // BANNIÈRE DE PRÉVENTION (STYLE IMAGE)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF9C4), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.withOpacity(0.3))),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCrypto == "USDT" 
                        ? "N’envoyez que des Tether USD (BEP20) à cette adresse. Les autres actifs seront perdus à jamais."
                        : "N’envoyez que des BNB pegged USD Coin (BEP20) à cette adresse. Les autres actifs seront perdus à jamais.",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            if (!isFromChat && !isShippingPayment) ...[
              const Text('1. Adresse de livraison', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(controller: _addressController, decoration: InputDecoration(hintText: 'Votre adresse complète', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
              const SizedBox(height: 30),
            ],
            
            Text(isFromChat ? '1. Scan & Transfert' : '2. Scan & Transfert', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Center(
              child: Column(
                children: [
                  QrImageView(data: _activeWallet, size: 160),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_selectedCrypto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)), child: const Text("BNB Smart Chain", style: TextStyle(fontSize: 10))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _activeWallet));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Adresse copiée !")));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: Text(_activeWallet, textAlign: TextAlign.center, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            Text(isFromChat ? '2. Preuve de paiement' : '3. Preuve de paiement', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(controller: _hashController, decoration: InputDecoration(hintText: 'Collez le Hash (TXID) ici...', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
            
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _confirmTransfer,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF283593), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : Text(isFromChat ? 'Confirmer le paiement' : 'Valider ma commande', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
