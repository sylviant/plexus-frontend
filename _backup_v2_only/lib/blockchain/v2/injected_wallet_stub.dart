import 'escrow_v2_config.dart';
import 'escrow_v2_errors.dart';
import 'escrow_v2_ports.dart';

/// Browser-extension wallet (MetaMask, Rabby…): only exists on web. On phones and desktop apps this stand-in
/// reports "not available", and WalletConnect is used instead.
class InjectedWalletService implements TxSender {
  InjectedWalletService({this.config = const EscrowV2Config()});
  final EscrowV2Config config;

  static bool get isAvailable => false;

  @override
  bool get isConnected => false;

  @override
  String? get address => null;

  Future<String> connect() => throw const EscrowException('NO_WALLET', 'Browser wallets are only available on the web version.');

  @override
  Future<String> sendTransaction({required String to, required String data, String valueHex = '0x0'}) =>
      throw const EscrowException('NO_WALLET', 'Browser wallets are only available on the web version.');
}
