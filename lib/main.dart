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
import 'package:intl/date_symbol_data_local.dart'; // AJOUTÉ

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialisation des dates pour éviter les crashs sur Notifications
  await initializeDateFormatting('fr_FR', null);

  try {
await Firebase.initializeApp(
  options: kIsWeb ? const FirebaseOptions(
    apiKey: "AIzaSyCDmt7Zk59s1i6xwO7TVSoBmlpnZgUA1L4",
    authDomain: "plexus-7d092.firebaseapp.com",
    projectId: "plexus-7d092",
    storageBucket: "plexus-7d092.firebasestorage.app",
    messagingSenderId: "717379042432",
    appId: "1:717379042432:web:e422d40a743c978a2cfa65",
    measurementId: "G-4TGV4HBBTX",
  ) : null,
);    await NotificationService.init();
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
    const Color primaryColor = Color(0xFF1A237E);

    return MaterialApp.router(
      title: 'PLEXUS',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          secondary: const Color(0xFFFBC02D),
          surface: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: const EdgeInsets.all(20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
        ),
      ),
      routerConfig: createRouter(context),
    );
  }
}
