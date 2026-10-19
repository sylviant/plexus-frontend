import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:plexus/l10n/l10n.dart';

class WalletService {
  static const String projectId = 'c5d461f849457d1fa9c1f03693707c6d';

  Web3App?     _web3app;
  SessionData? _session;
  Function()?  onConnected;

  String? get adresseConnectee {
    if (_session == null) return null;
    final accounts = _session!.namespaces['eip155']?.accounts;
    if (accounts == null || accounts.isEmpty) return null;
    return accounts.first.split(':').last;
  }

  bool get estConnecte => _session != null;

  Future<String?> init() async {
    _web3app = await Web3App.createInstance(
      projectId: projectId,
      metadata: PairingMetadata(
        name: 'PLEXUS',
        description: l10n.marketplaceDeLivraisonCommunautaire,
        url: 'https://plexus.app',
        icons: ['https://plexus.app/icon.png'],
      ),
    );

    final connectResponse = await _web3app!.connect(
      requiredNamespaces: {
        'eip155': const RequiredNamespace(
          chains: ['eip155:56'],
          methods: ['eth_sendTransaction', 'personal_sign'],
          events: ['chainChanged', 'accountsChanged'],
        ),
      },
    );

    // Écoute la session
    connectResponse.session.future.then((session) {
      _session = session;
      onConnected?.call();
    }).catchError((e) {
      print('=== ERREUR SESSION: $e ===');
    });

    final uri = connectResponse.uri?.toString();

    return uri;
  }

  // ── Ouvre le wallet mobile via deep link ──────────────────────────────────
Future<List<Map<String, String>>> getWalletsDisponibles(String uri) async {
  final String encodedUri = Uri.encodeComponent(uri);

  final List<Map<String, String>> wallets = [
    {'name': 'MetaMask',      'deeplink': 'metamask://wc?uri=$encodedUri',                         'icon': 'assets/wallets/metamask.png'},
    {'name': 'Trust Wallet',  'deeplink': 'trust://wc?uri=$encodedUri',                            'icon': 'assets/wallets/trust.png'},
    {'name': 'Binance Web3',  'deeplink': 'bnc://app.binance.com/cedefi/wc?uri=$encodedUri',       'icon': 'assets/wallets/binance.png'},
    {'name': 'Coinbase',      'deeplink': 'cbwallet://wc?uri=$encodedUri',                         'icon': 'assets/wallets/coinbase.png'},
    {'name': 'Rainbow',       'deeplink': 'rainbow://wc?uri=$encodedUri',                          'icon': 'assets/wallets/rainbow.png'},
    {'name': 'SafePal',       'deeplink': 'safepal://wc?uri=$encodedUri',                          'icon': 'assets/wallets/safepal.png'},
    {'name': 'OKX Wallet',    'deeplink': 'okex://main/wc?uri=$encodedUri',                        'icon': 'assets/wallets/okx.png'},
    {'name': 'Crypto.com',    'deeplink': 'cryptowallet://wc?uri=$encodedUri',                     'icon': 'assets/wallets/cryptocom.png'},
  ];

  // Filtre uniquement les wallets installés sur l'appareil
  final List<Map<String, String>> disponibles = [];
  for (final wallet in wallets) {
    final uri = Uri.parse(wallet['deeplink']!);
    if (await canLaunchUrl(uri)) {
      disponibles.add(wallet);
    }
  }
  return disponibles;
}

Future<void> ouvrirWallet(String deeplink) async {
  await launchUrl(Uri.parse(deeplink),
      mode: LaunchMode.externalApplication);
}
  Future<void> deconnecter() async {
    if (_session != null && _web3app != null) {
      await _web3app!.disconnectSession(
        topic: _session!.topic,
        reason: WalletConnectError(code: 0, message: l10n.deconnexion),
      );
      _session = null;
    }
  }
}