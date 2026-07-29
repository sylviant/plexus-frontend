import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/cart_provider.dart';
import 'package:plexus/blockchain/wallet_service.dart';
import 'package:plexus/blockchain/escrow_contract.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';
import 'package:qr_flutter/qr_flutter.dart';

dependencies:
  flutter:
    sdk: flutter
  walletconnect_flutter_v2: ^2.4.1
  web3dart: ^2.7.3
  url_launcher: ^6.2.5
  http: ^1.2.1
  geolocator: ^12.0.0
  cupertino_icons: ^1.0.8
  go_router: ^14.1.2
  provider: ^6.1.2
  dash_chat_2: ^0.0.20
  socket_io_client: ^2.0.3
  shared_preferences: ^2.2.3
  flutter_secure_storage: ^9.1.1
  image_picker: ^1.1.2
  qr_flutter: ^4.1.0
  google_generative_ai: ^0.4.7
  intl: ^0.19.0
  flutter_local_notifications: ^17.2.2
  firebase_core: ^3.1.1
  firebase_auth: ^5.1.1
  google_sign_in: ^6.2.1
  firebase_messaging: ^15.0.3
  geocoding: ^3.0.0
  flutter_staggered_grid_view: ^0.7.0
  flutter_animate: ^4.5.0
  lottie: ^3.1.0
  animate_do: ^3.3.4
  rive: ^0.13.0
  native_glass_navbar: ^1.0.2


import 'package:flutter/material.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

class WalletService {
  static const String projectId = 'c5d461f849457d1fa9c1f03693707c6d';

  Web3App? _web3app;
  SessionData? _session;

  String? get adresseConnectee {
    if (_session == null) return null;
    final accounts = _session!.namespaces['eip155']?.accounts;
    if (accounts == null || accounts.isEmpty) return null;
    return accounts.first.split(':').last;
  }

  bool get estConnecte => _session != null;
  String? _wcUri;
  String? get wcUri => _wcUri;

  Future<String?> init() async {
    _web3app = await Web3App.createInstance(
      projectId: projectId,
      metadata: const PairingMetadata(
        name: 'PLEXUS',
        description: 'Marketplace de livraison communautaire',
        url: 'https://plexus.app',
        icons: ['https://plexus.app/icon.png'],
      ),
    );

    final connectResponse = await _web3app!.connect(
      requiredNamespaces: {
        'eip155': const RequiredNamespace(
          chains: ['eip155:97'],
          methods: ['eth_sendTransaction', 'personal_sign'],
          events: ['chainChanged', 'accountsChanged'],
        ),
      },
    );

    _wcUri = connectResponse.uri?.toString();

    connectResponse.session.future.then((session) {
      _session = session;
    });

    return _wcUri;
  }

  Future<void> deconnecter() async {
    if (_session != null && _web3app != null) {
      await _web3app!.disconnectSession(
        topic: _session!.topic,
        reason: const WalletConnectError(code: 0, message: 'Déconnexion'),
      );
      _session = null;
    }
  }
}




je veux etre clair moi c'est la dernier fois que j'essaye avec toi si c'est pas j'arrtate ca fais deja plus d 4h qu'on tourne carement a ront donc rassure de bien verifier tout et demande moi ce que tu as besoin