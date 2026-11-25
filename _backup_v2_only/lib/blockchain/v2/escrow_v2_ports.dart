/// What the payment logic needs from the wallet and from the chain. Small interfaces, so the logic can be tested
/// without a phone, and so the app never needs a private key: the wallet signs, the app only asks.
library;

import 'escrow_v2_models.dart';

/// Asks the user's wallet to sign and send a transaction.
abstract class TxSender {
  bool get isConnected;

  /// The connected wallet's address, or null when not connected.
  String? get address;

  /// Sends a transaction from the connected wallet and returns its hash. The user approves it in the wallet app.
  /// Throws an EscrowException (for example USER_REJECTED when the user says no).
  Future<String> sendTransaction({required String to, required String data, String valueHex = '0x0'});
}

class TxReceiptInfo {
  const TxReceiptInfo({required this.success, required this.blockNumber});
  final bool success;
  final int blockNumber;
}

/// Reads the chain.
abstract class ChainReader {
  /// The order with this number, or null when it does not exist on-chain (yet).
  Future<OrderInfo?> order(String orderRef);

  Future<BigInt> tokenBalance(String owner);
  Future<BigInt> allowance(String owner, String spender);
  Future<int> blockNumber();

  /// The receipt once the transaction is mined, otherwise null.
  Future<TxReceiptInfo?> receipt(String txHash);
}
