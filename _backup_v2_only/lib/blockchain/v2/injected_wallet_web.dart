import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'escrow_v2_config.dart';
import 'escrow_v2_errors.dart';
import 'escrow_v2_ports.dart';

/// Browser-extension wallet (MetaMask, Rabby…) through the standard `window.ethereum` provider (EIP-1193).
/// Same promise as WalletConnect: the app never sees a key, the extension shows each request and the user approves it.
class InjectedWalletService implements TxSender {
  InjectedWalletService({this.config = const EscrowV2Config()});
  final EscrowV2Config config;

  String? _address;

  static JSObject? get _provider {
    final eth = globalContext.getProperty<JSAny?>('ethereum'.toJS);
    return eth.isA<JSObject>() ? eth as JSObject : null;
  }

  /// True when a wallet extension is installed in this browser.
  static bool get isAvailable => _provider != null;

  @override
  bool get isConnected => _address != null;

  @override
  String? get address => _address;

  String get _chainHex => '0x${config.chainId.toRadixString(16)}';

  Future<dynamic> _request(String method, [List<Object?> params = const []]) async {
    final p = _provider;
    if (p == null) {
      throw const EscrowException('NO_WALLET', 'No browser wallet found. Install MetaMask or connect with WalletConnect.');
    }
    final args = {'method': method, 'params': params}.jsify() as JSObject;
    try {
      final result = await p.callMethod<JSPromise<JSAny?>>('request'.toJS, args).toDart;
      return result.dartify();
    } catch (e) {
      throw _mapError(e);
    }
  }

  int? _codeOf(Object e) {
    try {
      final c = (e as JSObject).getProperty<JSAny?>('code'.toJS).dartify();
      return c is num ? c.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  EscrowException _mapError(Object e) {
    if (e is EscrowException) return e;
    final code = _codeOf(e);
    if (code == 4001) {
      return EscrowException('USER_REJECTED', 'You rejected the request in your wallet. Nothing was paid.', cause: e);
    }
    if (code == 4902) return EscrowException('UNKNOWN_CHAIN', 'Your wallet does not know ${config.chainName} yet.', cause: e);
    return interpretError(e);
  }

  /// Asks the extension to connect, and to switch to (or add) the configured network. Returns the address.
  Future<String> connect() async {
    final accounts = await _request('eth_requestAccounts');
    if (accounts is! List || accounts.isEmpty) {
      throw const EscrowException('NOT_CONNECTED', 'Your wallet did not share an account.');
    }
    await _ensureChain();
    _address = accounts.first.toString();
    return _address!;
  }

  Future<void> _ensureChain() async {
    if ((await _request('eth_chainId')).toString().toLowerCase() == _chainHex) return;
    try {
      await _request('wallet_switchEthereumChain', [
        {'chainId': _chainHex}
      ]);
    } on EscrowException catch (e) {
      if (e.code != 'UNKNOWN_CHAIN') rethrow;
      await _request('wallet_addEthereumChain', [_chainParams()]);
      await _request('wallet_switchEthereumChain', [
        {'chainId': _chainHex}
      ]);
    }
  }

  Map<String, Object?> _chainParams() => {
        'chainId': _chainHex,
        'chainName': config.chainName,
        'nativeCurrency': {'name': config.chainId == 97 ? 'tBNB' : 'BNB', 'symbol': config.chainId == 97 ? 'tBNB' : 'BNB', 'decimals': 18},
        'rpcUrls': [config.effectiveRpcUrl],
        'blockExplorerUrls': [config.chainId == 97 ? 'https://testnet.bscscan.com' : 'https://bscscan.com'],
      };

  @override
  Future<String> sendTransaction({required String to, required String data, String valueHex = '0x0'}) async {
    final from = _address;
    if (from == null) throw const EscrowException('NOT_CONNECTED', 'Connect your wallet first.');
    // the user may have switched account or network in the extension since connecting
    final accounts = await _request('eth_accounts');
    if (accounts is! List || accounts.isEmpty || accounts.first.toString().toLowerCase() != from.toLowerCase()) {
      throw const EscrowException('WALLET_CHANGED', 'The account in your wallet changed. Connect again.');
    }
    await _ensureChain();
    final hash = await _request('eth_sendTransaction', [
      {'from': from, 'to': to, 'data': data, 'value': valueHex}
    ]);
    if (hash is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash)) {
      throw const EscrowException('BAD_WALLET_REPLY', 'The wallet did not return a transaction. Please try again.');
    }
    return hash;
  }
}
