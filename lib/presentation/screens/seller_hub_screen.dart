import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:go_router/go_router.dart';

class SellerHubScreen extends StatefulWidget {
  const SellerHubScreen({super.key});

  @override
  State<SellerHubScreen> createState() => _SellerHubScreenState();
}

class _SellerHubScreenState extends State<SellerHubScreen> {
  List<dynamic> _myProducts = [];
  bool _isLoading = true;
  double _balance = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchSellerData();
  }

  Future<void> _fetchSellerData() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;
    try {
      final resP = await http.get(Uri.parse('${ApiConfig.baseUrl}/products/seller/${user.id}'));
      final resB = await http.get(Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/balance'));
      if (mounted) {
        setState(() {
          if (resP.statusCode == 200) _myProducts = json.decode(resP.body)['products'];
          if (resB.statusCode == 200) _balance = (json.decode(resB.body)['balance'] as num).toDouble();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5,
        title: const Text('HUB VENDEUR', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.redAccent), onPressed: () => auth.logout()),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchSellerData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- CARTE DE SOLDE PREMIUM ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [primaryColor, Color(0xFF3949AB)]),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: Column(
                  children: [
                    const Text("SOLDE DISPONIBLE", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Text("\$${_balance.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      child: const Text("DEMANDER UN RETRAIT", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),

              // --- RESTAURATION DES FONCTIONNALITÉS MANQUANTES (Cartes de Menu) ---
              const Text("MON ACTIVITÉ", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 15),
              
              _buildMenuCard(Icons.card_giftcard_rounded, "Parrainage & Gains", Colors.orange, () => context.push('/profile/referral')),
              _buildMenuCard(Icons.shopping_bag_outlined, "Historique des achats", Colors.green, () => context.push('/profile/orders')),
              _buildMenuCard(Icons.favorite_outline_rounded, "Mes Favoris", Colors.pink, () => context.push('/profile/favorites')),
              _buildMenuCard(Icons.account_balance_wallet_outlined, "Portefeuilles Crypto", Colors.deepPurple, () => context.push('/profile/payment-methods')),
              _buildMenuCard(Icons.location_on_outlined, "Adresses de livraison", Colors.red, () {}),

              const SizedBox(height: 40),
              
              // --- SECTION ARTICLES ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("MES ARTICLES EN VENTE", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: primaryColor)),
                  TextButton.icon(
                    onPressed: () => context.push('/profile/add-product'), 
                    icon: const Icon(Icons.add_circle_outline, size: 18), 
                    label: const Text("PUBLIER", style: TextStyle(fontWeight: FontWeight.bold))
                  ),
                ],
              ),
              const SizedBox(height: 15),

              if (_isLoading) const Center(child: CircularProgressIndicator())
              else if (_myProducts.isEmpty) _buildEmptyState()
              else GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, crossAxisSpacing: 15, mainAxisSpacing: 15),
                itemCount: _myProducts.length,
                itemBuilder: (context, i) => _buildSellerProductCard(_myProducts[i]),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(IconData icon, String title, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey[200]),
          const SizedBox(height: 15),
          const Text("Aucun article publié", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSellerProductCard(dynamic p) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.network(ApiConfig.getImageUrl(p['thumbnail']), width: double.infinity, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.broken_image)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("\$${p['price']}", style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.w900)),
                    GestureDetector(onTap: () => context.push('/profile/add-product', extra: p), child: const Icon(Icons.edit_note, color: Colors.blue, size: 20)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
