import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;

  Future<void> _pickImage() async {
    final XFile? selected = await _picker.pickImage(source: ImageSource.gallery);
    if (selected != null) {
      setState(() => _imageFile = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('MON COMPTE', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.settings_suggest_rounded, color: primaryColor), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- HEADER PROFIL LUXE ---
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(50), bottomRight: Radius.circular(50)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
              ),
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primaryColor.withOpacity(0.2), width: 2)),
                        child: CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.grey[100],
                          backgroundImage: _imageFile != null
                              ? FileImage(File(_imageFile!.path))
                              : (user?.profileImage != null ? NetworkImage(user!.profileImage!) : null) as ImageProvider?,
                          child: (_imageFile == null && user?.profileImage == null)
                              ? const Icon(Icons.person_rounded, size: 50, color: primaryColor)
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0, right: 4,
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: primaryColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)]),
                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(user?.firstName ?? 'Utilisateur PLEXUS', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: primaryColor)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
                    child: Text('PROFIL ACTIF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green[700], letterSpacing: 1)),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),

            // --- SECTIONS DE MENU ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("GÉNÉRAL", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
                  const SizedBox(height: 15),
                  _buildPremiumTile(Icons.person_outline_rounded, "Éditer le profil", Colors.blue, () {}),
                  _buildPremiumTile(Icons.card_giftcard_rounded, "Parrainage & Gains", Colors.orange, () => context.push('/profile/referral')),
                  
                  const SizedBox(height: 25),
                  const Text("COMMANDES & ACHATS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
                  const SizedBox(height: 15),
                  _buildPremiumTile(Icons.shopping_bag_outlined, "Historique des achats", Colors.green, () => context.push('/profile/orders')),
                  _buildPremiumTile(Icons.favorite_outline_rounded, "Mes Favoris", Colors.pink, () => context.push('/profile/favorites')),
                  
                  const SizedBox(height: 25),
                  const Text("PAIEMENT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
                  const SizedBox(height: 15),
                  _buildPremiumTile(Icons.account_balance_wallet_outlined, "Portefeuilles Crypto", Colors.deepPurple, () => context.push('/profile/payment-methods')),
                  _buildPremiumTile(Icons.location_on_outlined, "Adresses de livraison", Colors.red, () {}),
                  
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => auth.logout(),
                      icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      label: const Text("DÉCONNEXION", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.all(20), backgroundColor: Colors.red.withOpacity(0.05), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumTile(IconData icon, String title, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
