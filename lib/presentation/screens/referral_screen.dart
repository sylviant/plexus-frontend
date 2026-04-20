import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;
    final String referralCode = auth.myReferralCode ?? "PLEXUS-${user?.id.substring(0, 5).toUpperCase() ?? 'USER'}";
    final String shareLink = "https://plexus-app.com/join/$referralCode";

    const Color primaryColor = Color(0xFF283593);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Parrainage', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            // Illustration / Icon
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.card_giftcard_rounded, size: 80, color: primaryColor),
            ),
            const SizedBox(height: 30),
            
            const Text(
              "Invitez vos amis & Gagnez !",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            Text(
              "Partagez votre code et profitez de réductions sur vos frais de transaction et gagnez des commissions sur les ventes de vos amis.",
              style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 40),

            // Statistiques de parrainage
            Row(
              children: [
                _buildStatCard("Amis invités", "0", Colors.blue),
                const SizedBox(width: 15),
                _buildStatCard("Gains cumulés", "${auth.referralEarnings.toStringAsFixed(2)}\$", Colors.green),
              ],
            ),
            
            const SizedBox(height: 40),

            // Section Code de parrainage
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Votre code unique", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      referralCode,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: primaryColor),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: referralCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Code copié !"), backgroundColor: Colors.green),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Bouton de partage
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: "Rejoins-moi sur PLEXUS ! Utilise mon code : $referralCode pour bénéficier de réductions sur tes achats. Télécharge ici : $shareLink"));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Lien de partage copié dans le presse-papier !"), backgroundColor: primaryColor),
                  );
                },
                icon: const Icon(Icons.share, color: Colors.white),
                label: const Text("INVITER DES AMIS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Note d'économie (Filleul)
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined, color: Colors.green),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      "Économies réalisées grâce au parrainage : ${auth.referralSavings.toStringAsFixed(2)}\$",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
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

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
