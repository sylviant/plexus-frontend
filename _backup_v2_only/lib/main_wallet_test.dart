import 'package:flutter/material.dart';
import 'package:plexus/dev/wallet_test_page.dart';

/// DEVELOPMENT ONLY entry point for the V2 wallet test bench:
///   flutter run -d chrome --web-port 8080 -t lib/main_wallet_test.dart
void main() => runApp(const MaterialApp(
  title: 'PLEXUS wallet test',
  debugShowCheckedModeBanner: false,
  home: WalletTestPage(),
));
