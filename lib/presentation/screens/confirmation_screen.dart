import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic>? order; // Reçoit les infos de la commande

  const ConfirmationScreen({this.order, super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF283593);
    final String orderId = order?['_id']?.toString().substring(0, 8).toUpperCase() ?? "INCONNUE";

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Icone Animée
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 120,
              ),
              const SizedBox(height: 30),
              const Text(
                "Paiement Réussi !",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Text(
                "Votre commande #$orderId a été validée et enregistrée dans la Blockchain.",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              
              // Bouton pour voir le détail
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (order != null) {
                      context.push('/profile/orders/detail', extra: order);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 0,
                  ),
                  child: const Text("Voir le détail de la commande", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 15),

              // Bouton Retour
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 0,
                  ),
                  child: const Text("Retour à l'accueil", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
