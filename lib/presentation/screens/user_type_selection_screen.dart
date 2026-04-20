import 'package:flutter/material.dart';
import 'package:plexus/core/models/user_type.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:provider/provider.dart';

class UserTypeSelectionScreen extends StatelessWidget {
  const UserTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Bienvenue sur Plexus",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              "Comment souhaitez-vous utiliser l'application ?",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () {
                Provider.of<UserProvider>(context, listen: false)
                    .setUserType(UserType.client);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
              ),
              child: const Text("Je suis un client"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Provider.of<UserProvider>(context, listen: false)
                    .setUserType(UserType.seller);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 50),
              ),
              child: const Text("Je suis un vendeur"),
            ),
          ],
        ),
      ),
    );
  }
}
