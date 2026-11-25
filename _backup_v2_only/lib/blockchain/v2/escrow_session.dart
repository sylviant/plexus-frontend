import 'package:web3dart/crypto.dart' show bytesToHex;

import 'escrow_api.dart';
import 'escrow_payment_flow.dart';
import 'escrow_v2_calldata.dart';
import 'escrow_v2_config.dart';
import 'escrow_v2_errors.dart';
import 'escrow_v2_ports.dart';
import 'escrow_v2_service.dart';
import 'injected_wallet.dart';
import 'wallet_connect_service.dart';
import 'web3_chain_reader.dart';

/// One wallet connection for the whole app: the payment screen and the order screen share it, so the user connects
/// once. The app never holds a private key: the wallet (WalletConnect, or a browser extension on web) signs.
class EscrowSession {
  EscrowSession._();
  static final EscrowSession instance = EscrowSession._();

  final EscrowV2Config config = const EscrowV2Config();
  late final WalletConnectService _wc = WalletConnectService(config: config);
  late final InjectedWalletService _injected = InjectedWalletService(config: config);
  late final Web3ChainReader _reader = Web3ChainReader(config);

  TxSender? _sender;

  /// The connected wallet, or null.
  TxSender? get sender => (_sender?.isConnected ?? false) ? _sender : null;
  String? get address => sender?.address;
  bool get isConnected => sender != null;

  /// True on web when a wallet extension (MetaMask...) is installed.
  bool get browserWalletAvailable => InjectedWalletService.isAvailable;

  /// Connects the browser extension wallet (web only). Returns the address.
  Future<String> connectBrowserWallet() async {
    final a = await _injected.connect();
    _sender = _injected;
    return a;
  }

  /// Starts a WalletConnect pairing. Returns the link to show as a QR code or open in a wallet app, or null when a
  /// wallet is already connected. [onConnected] fires when the user approves in the wallet.
  Future<String?> startWalletConnect({required void Function() onConnected}) {
    _wc.onConnected = () {
      _sender = _wc;
      onConnected();
    };
    return _wc.startPairing();
  }

  Future<void> disconnect() async {
    final s = _sender;
    _sender = null;
    if (identical(s, _wc)) await _wc.disconnect();
  }

  EscrowV2Service get service {
    final s = sender;
    if (s == null) throw const EscrowException('NOT_CONNECTED', 'Connect your wallet first.');
    return EscrowV2Service(config: config, sender: s, reader: _reader);
  }

  /// The one call a payment screen makes: [EscrowPaymentFlow.payOrder].
  EscrowPaymentFlow paymentFlow({required String baseUrl, required Future<String?> Function() authToken}) =>
      EscrowPaymentFlow(service: service, api: HttpEscrowApi(baseUrl: baseUrl, authToken: authToken));

  /// The 32-byte order number used on-chain for a PLEXUS order id: keccak256 of the id's text.
  /// The backend must sign its quotes with the same value as `orderRef`.
  static String orderRefFor(String orderId) => '0x${bytesToHex(EscrowV2Calldata.hashText(orderId))}';
}
