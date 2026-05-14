import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _selectedCrypto = "USDT";

  static const String _walletAddress = "0x772b9729B0c76cDf4e9295e32664ff01E5757358";

  @override
  void initState() {
    super.initState();
    // Pré-remplir l'adresse si elle existe dans le profil
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    // Si vous avez l'adresse dans le provider, vous pouvez la mettre ici
  }

  @override
  void dispose() {
    _hashController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _confirmTransfer() async {
    HapticFeedback.mediumImpact();
    if (_hashController.text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un Hash (TXID) valide.'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veuillez entrer une adresse de livraison.")));
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() => _isSubmitting = true);

    try {
      final bool isFromChat = widget.productData?['orderId'] != null;
      
      if (isFromChat) {
        // --- CAS CHAT : On met à jour le statut ET on enregistre l'adresse ---
        final String orderId = widget.productData?['orderId'] ?? '';
        await http.put(
          Uri.parse('${ApiConfig.baseUrl}/orders/$orderId/status'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'status': 'PAID',
            'transactionHash': _hashController.text,
            'cryptoType': _selectedCrypto,
            'deliveryAddress': _addressController.text, // On envoie l'adresse ici aussi
          }),
        );
        if (mounted) context.go('/profile/orders');
      } else {
        // --- CAS PANIER : Nouvelle commande ---
        final orderData = {
          'userId': auth.currentUser!.id,
          'buyerName': auth.currentUser!.firstName,
          'deliveryAddress': _addressController.text,
          'items': cart.items.values.map((item) => {'title': item.title, 'price': item.price, 'quantity': item.quantity}).toList(),
          'totalAmount': cart.totalPrice,
          'sellerId': widget.productData?['sellerId'] ?? 'Inconnu',
          'transactionHash': _hashController.text,
          'cryptoType': _selectedCrypto,
          'status': 'PENDING_SHIPPING',
        };
        final response = await http.post(Uri.parse('${ApiConfig.baseUrl}/orders'), headers: {'Content-Type': 'application/json'}, body: json.encode(orderData));
        if (response.statusCode == 201) { cart.clear(); if (mounted) context.go('/cart/confirmation', extra: json.decode(response.body)); }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally { if (mounted) setState(() => _isSubmitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);
    final cart = Provider.of<CartProvider>(context);
    final dynamic passedPriceRaw = widget.productData?['price'];
    final double passedPrice = (passedPriceRaw != null) ? double.parse(passedPriceRaw.toString()) : 0.0;
    final bool isFromChat = widget.productData?['orderId'] != null;
    final double displayPrice = isFromChat ? passedPrice : cart.totalPrice;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('PAIEMENT SÉCURISÉ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              width: double.infinity, padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]),
              child: Text('\$${displayPrice.toStringAsFixed(2)} $_selectedCrypto', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 30),
            
            // ADRESSE DE LIVRAISON (Toujours visible pour être sûr)
            const Align(alignment: Alignment.centerLeft, child: Text("ADRESSE DE LIVRAISON", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))),
            const SizedBox(height: 10),
            TextField(controller: _addressController, decoration: const InputDecoration(hintText: "Saisissez votre adresse de réception")),
            const SizedBox(height: 30),

            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'USDT', label: Text('USDT'), icon: Icon(Icons.currency_bitcoin)),
                ButtonSegment(value: 'USDC', label: Text('USDC'), icon: Icon(Icons.monetization_on_outlined)),
              ],
              selected: {_selectedCrypto},
              onSelectionChanged: (v) {
                HapticFeedback.lightImpact();
                setState(() => _selectedCrypto = v.first);
              },
            ),
            const SizedBox(height: 25),
            _buildWarningBanner(),
            const SizedBox(height: 30),

            // AFFICHAGE DES IMAGES QR CODE (Noms corrigés selon vos assets)
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
                  _selectedCrypto == "USDT" ? 'assets/images/usdt.png' : 'assets/images/usdc.png',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 220, height: 220, color: Colors.grey[100],
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 60, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("Image QR introuvable", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),
            const Text("BNB Smart Chain (BEP20)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Clipboard.setData(ClipboardData(text: _walletAddress));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Adresse copiée !")));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryColor.withOpacity(0.1))),
                child: const Text(_walletAddress, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ),
            const SizedBox(height: 30),
            const Align(alignment: Alignment.centerLeft, child: Text("PREUVE DE TRANSFERT (HASH TXID)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))),
            const SizedBox(height: 10),
            TextField(controller: _hashController, decoration: const InputDecoration(hintText: "Collez l'ID de transaction")),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity, height: 60,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _confirmTransfer,
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('CONFIRMER LE PAIEMENT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF9C4), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.withOpacity(0.3))),
      child: Row(children: [
        const Icon(Icons.info_outline, color: Colors.orange, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(_selectedCrypto == "USDT" ? "N’envoyez que des Tether USD (BEP20) à cette adresse. Les autres actifs seront perdus à jamais." : "N’envoyez que des BNB pegged USD Coin (BEP20) à cette adresse. Les autres actifs seront perdus à jamais.", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}
