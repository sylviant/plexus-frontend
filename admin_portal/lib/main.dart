import 'package:material_ui/material_ui.dart';
import 'package:plexus_admin/screens/dashboard_screen.dart';
import 'package:plexus_admin/screens/login_screen.dart';
import 'package:intl/date_symbol_data_local.dart'; // AJOUTÉ

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialisation des dates pour éviter les erreurs de formatage
  await initializeDateFormatting('fr_FR', null);
  
  runApp(const PlexusAdminApp());
}

class PlexusAdminApp extends StatelessWidget {
  const PlexusAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PLEXUS Control Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
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
