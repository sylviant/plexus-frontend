import 'package:flutter/material.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:plexus/core/providers/favorite_provider.dart';
import 'package:plexus/core/providers/category_provider.dart';
import 'package:plexus/core/router.dart';
import 'package:plexus/core/services/notification_service.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    await NotificationService.init();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProxyProvider<UserProvider, AuthProvider>(
          create: (_) => AuthProvider(),
          update: (_, userProvider, authProvider) =>
              authProvider!..updateUserProvider(userProvider),
        ),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => SocketProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => FavoriteProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
      ],
      child: const PlexusApp(),
    ),
  );
}

class PlexusApp extends StatefulWidget {
  const PlexusApp({super.key});

  @override
  State<PlexusApp> createState() => _PlexusAppState();
}

class _PlexusAppState extends State<PlexusApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.isAuthenticated && auth.currentUser != null) {
        final userId = auth.currentUser!.id;
        final notifProvider = Provider.of<NotificationProvider>(context, listen: false);
        
        Provider.of<SocketProvider>(context, listen: false).connect(userId, notifProvider);
        notifProvider.fetchNotifications(userId);
        Provider.of<FavoriteProvider>(context, listen: false).fetchFavorites(userId);

        if (!kIsWeb) {
          final token = await NotificationService.getFcmToken();
          if (token != null) {
            auth.updateFcmToken(token);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PLEXUS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          primary: const Color(0xFF1A237E),
          secondary: const Color(0xFFFBC02D),
          surface: Colors.white,
        ),
        // Typographie Moderne
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
          bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        // Style des Cartes (Correction: CardThemeData au lieu de CardTheme)
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        // Style des Boutons
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
          ),
        ),
        // Style des Inputs
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: const EdgeInsets.all(20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
          ),
        ),
      ),
      routerConfig: createRouter(context),
    );
  }
}
