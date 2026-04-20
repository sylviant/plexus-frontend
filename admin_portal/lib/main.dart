import 'package:flutter/material.dart';
import 'package:plexus_admin/screens/dashboard_screen.dart';
import 'package:plexus_admin/screens/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const PlexusAdminApp());
}

class PlexusAdminApp extends StatelessWidget {
  const PlexusAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PLEXUS Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const AdminLoginScreen(),
        '/dashboard': (context) => const AdminDashboard(),
      },
    );
  }
}
