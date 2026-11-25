import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/blockchain/v2/escrow_v2_calldata.dart';
import 'package:plexus/blockchain/v2/escrow_v2_config.dart';
import 'package:plexus/blockchain/v2/escrow_v2_errors.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';
import 'package:plexus/blockchain/v2/escrow_v2_ports.dart';
import 'package:plexus/blockchain/v2/escrow_v2_service.dart';

import 'fakes.dart';

void main() {
  final golden = jsonDecode(File('test/fixtures/escrow_v2_calldata.json').readAsStringSync()) as Map<String, dynamic>;
  final escrow = golden['escrow'] as String;
  final quote = SignedQuote.fromJson({...(golden['quote'] as Map<String, dynamic>), 'signature': golden['signature']});
  final total = quote.total; // $110
  final config = EscrowV2Config(chainId: 97, escrowAddress: escrow, tokenAddress: testTokenAddress, rpcUrl: 'http://x', confirmations: 3);
  final calldata = EscrowV2Calldata();

  // the quote expires at 2030-01-01; the test clock is a day before
  var now = DateTime.utc(2029, 12, 31);

  FakeWallet wallet = FakeWallet(quote.buyer);
  late FakeChain chain;
  late EscrowV2Service service;

  /// A wallet that "mines" what it is sent: approvals raise the allowance, everything gets a receipt.
  void connect({BigInt? balance, BigInt? allowance, Duration timeout = const Duration(seconds: 5)}) {
    wallet = FakeWallet(quote.buyer);
    chain = FakeChain(balance: balance ?? total * BigInt.from(5), allowanceValue: allowance ?? BigInt.zero);
    wallet.onSent = (tx) {
      if (tx.to == testTokenAddress) chain.allowanceValue = total;
      chain.receipts[tx.hash] = TxReceiptInfo(success: !chain.failTransactions, blockNumber: chain.head);
    };
    service = EscrowV2Service(
      config: config, sender: wallet, reader: chain, calldata: calldata,
      pollInterval: Duration.zero, timeout: timeout, clock: () => now,
    );
  }

  setUp(() {
    now = DateTime.utc(2029, 12, 31);
    connect();
  });

  group('paying a quote', () {
    test('approves exactly the total, then creates the order, in that order', () async {
      final steps = <PayStep>[];
      final r = await service.pay(quote, onStep: steps.add);

      expect(wallet.sent.length, 2);
      expect(wallet.sent[0].to, testTokenAddress);
      expect(wallet.sent[0].data, calldata.approve(escrow, total)); // exact amount, never "unlimited"
      expect(wallet.sent[1].to, escrow);
      expect(wallet.sent[1].data, calldata.createOrder(quote));
      expect(r.approveTx, wallet.sent[0].hash);
      expect(r.createOrderTx, wallet.sent[1].hash);
      expect(steps, [PayStep.checking, PayStep.approving, PayStep.creatingOrder, PayStep.confirming, PayStep.done]);
    });

    test('skips the approval when the allowance is already enough', () async {
      connect(allowance: total);
      final steps = <PayStep>[];
      final r = await service.pay(quote, onStep: steps.add);
      expect(wallet.sent.length, 1);
      expect(wallet.sent.single.data, calldata.createOrder(quote));
      expect(r.approveTx, isNull);
      expect(steps, isNot(contains(PayStep.approving)));
    });

    test('waits for the confirmations before it reports success', () async {
      connect(allowance: total);
      await service.pay(quote);
      // receipt in block 1000, three confirmations needed: the head must have moved to at least 1002
      expect(chain.head, greaterThanOrEqualTo(1002));
      expect(chain.blockNumberCalls, greaterThanOrEqualTo(2));
    });
  });

  group('nothing reaches the wallet when a check fails', () {
    test('an expired quote', () async {
      now = quote.expiresAt.add(const Duration(minutes: 1));
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'QUOTE_EXPIRED')));
      expect(wallet.sent, isEmpty);
    });
    test('a quote that would expire while the user is still approving (inside the safety margin)', () async {
      now = quote.expiresAt.subtract(const Duration(seconds: 20));
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'QUOTE_EXPIRED')));
      expect(wallet.sent, isEmpty);
    });
    test('a different wallet from the one the order was made for', () async {
      wallet.address = '0x00000000000000000000000000000000000000AA';
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'WRONG_WALLET')));
      expect(wallet.sent, isEmpty);
    });
    test('a wallet that is not connected', () async {
      wallet.isConnected = false;
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'NOT_CONNECTED')));
      expect(wallet.sent, isEmpty);
    });
    test('not enough USDT, with the amounts in the message', () async {
      connect(balance: total - BigInt.one);
      await expectLater(
        service.pay(quote),
        throwsA(isA<EscrowException>()
            .having((e) => e.code, 'code', 'INSUFFICIENT_USDT')
            .having((e) => e.message, 'message', allOf(contains('110.00 USDT'), contains('109.99 USDT')))),
      );
      expect(wallet.sent, isEmpty);
    });
  });

  group('when something goes wrong during the payment', () {
    test('the user rejects the approval: the order is never created', () async {
      wallet.rejectRequestNumber = 0;
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'USER_REJECTED')));
      expect(wallet.sent, isEmpty);
    });
    test('the user rejects the order after approving: only the approval was sent', () async {
      wallet.rejectRequestNumber = 1;
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'USER_REJECTED')));
      expect(wallet.sent.length, 1);
      expect(wallet.sent.single.to, testTokenAddress);
    });
    test('the quote runs out while the user is approving: no order is created', () async {
      wallet.onSent = (tx) {
        chain.allowanceValue = total;
        chain.receipts[tx.hash] = TxReceiptInfo(success: true, blockNumber: chain.head);
        now = quote.expiresAt.add(const Duration(minutes: 5)); // the user took too long
      };
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'QUOTE_EXPIRED')));
      expect(wallet.sent.length, 1);
    });
    test('the network rejects the transaction', () async {
      connect(allowance: total);
      chain.failTransactions = true;
      await expectLater(service.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'TX_FAILED')));
    });
    test('a transaction that is never mined ends with a clear timeout', () async {
      connect(allowance: total);
      chain.neverMine = true;
      var t = DateTime.utc(2029, 12, 31);
      final slow = EscrowV2Service(
        config: config, sender: wallet, reader: chain, calldata: calldata,
        pollInterval: Duration.zero, timeout: const Duration(minutes: 3),
        clock: () => t = t.add(const Duration(seconds: 10)), // time passes on every look at the clock
      );
      await expectLater(slow.pay(quote), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'TX_TIMEOUT')));
    });
  });

  group('order actions', () {
    test('withdrawals and confirmations go to the escrow with the right call data', () async {
      await service.withdrawRefund();
      await service.withdraw();
      await service.withdrawRewards();
      await service.confirmReceipt(quote.orderRef);
      expect(wallet.sent.map((t) => t.to).toSet(), {escrow});
      expect(wallet.sent.map((t) => t.data), [
        calldata.withdrawRefund(),
        calldata.withdraw(),
        calldata.withdrawRewards(),
        calldata.confirmReceipt(quote.orderRef),
      ]);
    });
    test('a dispute sends only the hash of the reason', () async {
      await service.openDispute(quote.orderRef, 'parcel never arrived');
      expect(wallet.sent.single.data, calldata.openDispute(quote.orderRef, EscrowV2Calldata.hashText('parcel never arrived')));
    });
    test('actions need a connected wallet', () async {
      wallet.isConnected = false;
      await expectLater(service.withdraw(), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'NOT_CONNECTED')));
      expect(wallet.sent, isEmpty);
    });
    test('accepting a higher delivery fee approves only the difference first', () async {
      final extra = BigInt.parse('15000000000000000000');
      await service.acceptDeliveryAdjustment(quote.orderRef, extraAmount: extra);
      expect(wallet.sent.length, 2);
      expect(wallet.sent[0].data, calldata.approve(escrow, extra));
      expect(wallet.sent[1].data, calldata.acceptDeliveryAdjustment(quote.orderRef));
    });
    test('accepting is refused before the wallet is asked when the balance is too low', () async {
      connect(balance: BigInt.one);
      await expectLater(
        service.acceptDeliveryAdjustment(quote.orderRef, extraAmount: BigInt.parse('15000000000000000000')),
        throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'INSUFFICIENT_USDT')),
      );
      expect(wallet.sent, isEmpty);
    });
  });

  group('error messages', () {
    test('contract errors are recognised from the revert code the wallet or node returns', () {
      expect(interpretError(Exception('execution reverted: 0x472e017e')).code, 'NotBuyer');
      expect(interpretError(Exception('execution reverted: 0x5cd5d233')).code, 'BadSignature');
      expect(interpretError(Exception('reverted with custom error QuoteExpired()')).code, 'QuoteExpired');
      expect(interpretError(Exception('execution reverted: 0x472e017e')).message, 'Only the buyer can do this.');
    });
    test('a rejection, missing gas and the unknown', () {
      expect(interpretError(Exception('User rejected the request.')).code, 'USER_REJECTED');
      expect(interpretError(Exception('insufficient funds for gas * price + value')).code, 'INSUFFICIENT_GAS');
      final unknown = interpretError(Exception('socket closed 0xdeadbeef'));
      expect(unknown.code, 'UNKNOWN');
      expect(unknown.message, isNot(contains('socket'))); // internal details are not shown to the user
    });
  });
}
