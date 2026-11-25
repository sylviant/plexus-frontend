import 'package:plexus/blockchain/v2/escrow_v2_errors.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';
import 'package:plexus/blockchain/v2/escrow_v2_ports.dart';

/// Shared by the blockchain tests: a fake wallet and a fake chain, so nothing here needs a phone or a network.

const testTokenAddress = '0x21c2Ecb70b260dB100c9ab44592739F4da6C8C14';

class SentTx {
  SentTx(this.to, this.data, this.hash);
  final String to;
  final String data;
  final String hash;
}

/// Pretends to be the user's wallet. The user can reject the n-th request.
class FakeWallet implements TxSender {
  FakeWallet(this.address);
  @override
  String? address;
  @override
  bool isConnected = true;
  final sent = <SentTx>[];
  int? rejectRequestNumber; // 0 = the first request
  void Function(SentTx tx)? onSent;

  @override
  Future<String> sendTransaction({required String to, required String data, String valueHex = '0x0'}) async {
    if (rejectRequestNumber == sent.length) {
      throw const EscrowException('USER_REJECTED', 'You rejected the request in your wallet. Nothing was paid.');
    }
    final tx = SentTx(to, data, '0x${(sent.length + 1).toRadixString(16).padLeft(64, '0')}');
    sent.add(tx);
    onSent?.call(tx);
    return tx.hash;
  }
}

/// Pretends to be the blockchain: every block queried is one block newer.
class FakeChain implements ChainReader {
  FakeChain({required this.balance, required this.allowanceValue});
  BigInt balance;
  BigInt allowanceValue;
  int head = 1000;
  int blockNumberCalls = 0;
  bool neverMine = false;
  bool failTransactions = false;
  final receipts = <String, TxReceiptInfo>{};
  OrderInfo? orderInfo; // what getOrder returns; null means "no such order"

  @override
  Future<OrderInfo?> order(String orderRef) async => orderInfo;
  @override
  Future<BigInt> tokenBalance(String owner) async => balance;
  @override
  Future<BigInt> allowance(String owner, String spender) async => allowanceValue;
  @override
  Future<int> blockNumber() async {
    blockNumberCalls++;
    return head += 1;
  }

  @override
  Future<TxReceiptInfo?> receipt(String txHash) async => neverMine ? null : receipts[txHash];
}
