import 'dart:async';

import 'package:url_launcher/url_launcher.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

import 'escrow_v2_config.dart';
import 'escrow_v2_errors.dart';
import 'escrow_v2_ports.dart';

/// Connects the user's own wallet through WalletConnect and asks it to sign transactions (task 2.1).
/// The app never sees a private key: it sends a request, the wallet shows it, the user approves or rejects.
class WalletConnectService implements TxSender {
  WalletConnectService({
    this.config = const EscrowV2Config(),
    this.projectId = const String.fromEnvironment('WC_PROJECT_ID', defaultValue: 'c5d461f849457d1fa9c1f03693707c6d'),
  });

  final EscrowV2Config config;
  final String projectId;

  Web3App? _app;
  SessionData? _session;

  /// Called once a wallet has connected on the right network.
  void Function()? onConnected;

  /// Called when the wallet disconnects.
  void Function()? onDisconnected;

  @override
  bool get isConnected => _session != null && address != null;

  /// The wallet address on the configured network, or null when not connected.
  @override
  String? get address {
    final accounts = _session?.namespaces['eip155']?.accounts;
    if (accounts == null) return null;
    final prefix = '${config.caip2}:';
    for (final a in accounts) {
      if (a.startsWith(prefix)) return a.substring(prefix.length);
    }
    return null;
  }

  Future<void> _ensureApp() async {
    if (_app != null) return;
    final app = await Web3App.createInstance(
      projectId: projectId,
      metadata: const PairingMetadata(
        name: 'PLEXUS',
        description: 'PLEXUS marketplace',
        url: 'https://plexus.app',
        icons: ['https://plexus.app/icon.png'],
      ),
    );
    app.onSessionDelete.subscribe((_) {
      _session = null;
      onDisconnected?.call();
    });
    _app = app;
    // Reuse a wallet that is already connected on this network (the session survives app restarts).
    for (final s in app.sessions.getAll().reversed) {
      _session = s;
      if (address != null) return;
      _session = null;
    }
  }

  /// Starts a connection and returns the WalletConnect link (shown as a QR code, or opened in a wallet app).
  /// [onConnected] fires when the user approves it in the wallet. Returns null when a wallet is already connected.
  Future<String?> startPairing() async {
    await _ensureApp();
    if (isConnected) {
      onConnected?.call();
      return null;
    }
    final response = await _app!.connect(
      requiredNamespaces: {
        'eip155': RequiredNamespace(
          chains: [config.caip2],
          methods: const ['eth_sendTransaction', 'personal_sign'],
          events: const ['chainChanged', 'accountsChanged'],
        ),
      },
    );
    unawaited(response.session.future.then((session) async {
      _session = session;
      if (address == null) {
        // the wallet connected, but not on our network
        await disconnect();
        throw EscrowException('WRONG_CHAIN',
            'Your wallet connected to a different network. Switch it to ${config.chainName} and connect again.');
      }
      onConnected?.call();
    }).catchError((Object _) {
      _session = null;
    }));
    return response.uri?.toString();
  }

  @override
  Future<String> sendTransaction({required String to, required String data, String valueHex = '0x0'}) async {
    final app = _app;
    final session = _session;
    final from = address;
    if (app == null || session == null || from == null) {
      throw const EscrowException('NOT_CONNECTED', 'Connect your wallet first.');
    }
    unawaited(_openWallet(session)); // bring the wallet app forward so the user sees the request
    try {
      final result = await app.request(
        topic: session.topic,
        chainId: config.caip2,
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [
            {'from': from, 'to': to, 'data': data, 'value': valueHex},
          ],
        ),
      );
      if (result is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(result)) {
        throw const EscrowException('BAD_WALLET_REPLY', 'The wallet did not return a transaction. Please try again.');
      }
      return result;
    } on EscrowException {
      rethrow;
    } catch (e) {
      throw _mapWalletError(e);
    }
  }

  EscrowException _mapWalletError(Object e) {
    int? code;
    if (e is JsonRpcError) code = e.code;
    if (e is WalletConnectError) code = e.code;
    // 5000 is WalletConnect's "user rejected", 4001 is the standard wallet code for the same thing
    if (code == 5000 || code == 4001) {
      return EscrowException('USER_REJECTED', 'You rejected the request in your wallet. Nothing was paid.', cause: e);
    }
    return interpretError(e);
  }

  Future<void> _openWallet(SessionData session) async {
    final redirect = session.peer.metadata.redirect;
    final link = redirect?.native ?? redirect?.universal;
    if (link == null || link.isEmpty) return;
    try {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (_) {
      // best effort: the user can also open the wallet by hand
    }
  }

  Future<void> disconnect() async {
    final app = _app;
    final session = _session;
    _session = null;
    if (app != null && session != null) {
      try {
        await app.disconnectSession(topic: session.topic, reason: Errors.getSdkError(Errors.USER_DISCONNECTED));
      } catch (_) {}
    }
  }

  // ---- wallet apps installed on the phone, to open the connection request directly -----------
  Future<List<Map<String, String>>> availableWallets(String uri) async {
    final encoded = Uri.encodeComponent(uri);
    final all = <Map<String, String>>[
      {'name': 'MetaMask', 'deeplink': 'metamask://wc?uri=$encoded', 'icon': 'assets/wallets/metamask.png'},
      {'name': 'Trust Wallet', 'deeplink': 'trust://wc?uri=$encoded', 'icon': 'assets/wallets/trust.png'},
      {'name': 'Binance Web3', 'deeplink': 'bnc://app.binance.com/cedefi/wc?uri=$encoded', 'icon': 'assets/wallets/binance.png'},
      {'name': 'Coinbase', 'deeplink': 'cbwallet://wc?uri=$encoded', 'icon': 'assets/wallets/coinbase.png'},
      {'name': 'Rainbow', 'deeplink': 'rainbow://wc?uri=$encoded', 'icon': 'assets/wallets/rainbow.png'},
      {'name': 'SafePal', 'deeplink': 'safepal://wc?uri=$encoded', 'icon': 'assets/wallets/safepal.png'},
      {'name': 'OKX Wallet', 'deeplink': 'okex://main/wc?uri=$encoded', 'icon': 'assets/wallets/okx.png'},
      {'name': 'Crypto.com', 'deeplink': 'cryptowallet://wc?uri=$encoded', 'icon': 'assets/wallets/cryptocom.png'},
    ];
    final installed = <Map<String, String>>[];
    for (final w in all) {
      if (await canLaunchUrl(Uri.parse(w['deeplink']!))) installed.add(w);
    }
    return installed;
  }

  Future<void> openWallet(String deeplink) => launchUrl(Uri.parse(deeplink), mode: LaunchMode.externalApplication);
}
