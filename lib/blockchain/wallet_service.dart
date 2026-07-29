import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

class WalletService {
  static const String projectId = 'c5d461f849457d1fa9c1f03693707c6d';

  Web3App? _web3app;
  SessionData? _session;
  Function()? onConnected;

  String? get adresseConnectee {
    if (_session == null) return null;
    final accounts = _session!.namespaces['eip155']?.accounts;
    if (accounts == null || accounts.isEmpty) return null;
    return accounts.first.split(':').last;
  }

  bool get estConnecte => _session != null;

  Future<String?> init() async {
    print('=== INIT WALLETCONNECT ===');
    _web3app = await Web3App.createInstance(
      projectId: projectId,
      metadata: const PairingMetadata(
        name: 'PLEXUS',
        description: 'Marketplace de livraison communautaire',
        url: 'https://plexus.app',
        icons: ['https://plexus.app/icon.png'],
      ),
    );
    print('=== WEB3APP CRÉÉ ===');

    final connectResponse = await _web3app!.connect(
      requiredNamespaces: {
        'eip155': const RequiredNamespace(
          chains: ['eip155:97'],
          methods: ['eth_sendTransaction', 'personal_sign'],
          events: ['chainChanged', 'accountsChanged'],
        ),
      },
    );

    print('=== URI GÉNÉRÉ: ${connectResponse.uri} ===');

    connectResponse.session.future.then((session) {
      print('=== SESSION ÉTABLIE: ${session.peer.metadata.name} ===');
      print('=== ADRESSE: ${session.namespaces} ===');
      _session = session;
      onConnected?.call();
    }).catchError((e) {
      print('=== ERREUR SESSION: $e ===');
    });

    return connectResponse.uri?.toString();
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