import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/blockchain/v2/escrow_v2_abi.g.dart';
import 'package:plexus/blockchain/v2/escrow_v2_calldata.dart';
import 'package:plexus/blockchain/v2/escrow_v2_config.dart';
import 'package:plexus/blockchain/v2/escrow_v2_errors.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';
import 'package:plexus/blockchain/v2/escrow_v2_ports.dart';
import 'package:plexus/blockchain/v2/escrow_v2_service.dart';
import 'package:web3dart/web3dart.dart';

import 'fakes.dart';

void main() {
  final golden = jsonDecode(File('test/fixtures/escrow_v2_calldata.json').readAsStringSync()) as Map<String, dynamic>;
  final escrow = golden['escrow'] as String;
  final orderGolden = golden['getOrderResult'] as Map<String, dynamic>;
  final expected = orderGolden['expected'] as Map<String, dynamic>;

  group('reading an order from the chain', () {
    test('the app reads the right field from every position of the contract\'s answer', () {
      final abi = ContractAbi.fromJson(escrowV2Abi, 'PlexusEscrowV2');
      final fn = abi.functions.firstWhere((f) => f.name == 'getOrder');
      final decoded = fn.decodeReturnValues(orderGolden['hex'] as String);
      final info = OrderInfo.fromAbiResult(decoded.first as List<dynamic>);

      expect(info.status, expected['status']);
      expect(info.statusName, 'Delivery change proposed');
      expect(info.buyer.toLowerCase(), (expected['buyer'] as String).toLowerCase());
      expect(info.seller.toLowerCase(), (expected['seller'] as String).toLowerCase());
      expect(info.productAmount, BigInt.parse(expected['productAmount'] as String));
      expect(info.deliveryAmount, BigInt.parse(expected['deliveryAmount'] as String));
      expect(info.proposedDelivery, BigInt.parse(expected['proposedDelivery'] as String));
      expect(info.adjustmentDeadline, expected['adjustmentDeadline']);
      expect(info.extraToPay, BigInt.parse(expected['extraToPay'] as String)); // 25 - 10 = 15
    });

    test('a lower proposal asks for nothing extra', () {
      final info = OrderInfo(
        status: 2, buyer: 'a', seller: 'b', productAmount: BigInt.from(100), deliveryAmount: BigInt.from(10),
        proposedDelivery: BigInt.from(4), adjustmentDeadline: 1,
      );
      expect(info.extraToPay, BigInt.zero);
    });
  });

  group('answering a delivery fee change', () {
    final config = EscrowV2Config(chainId: 97, escrowAddress: escrow, tokenAddress: testTokenAddress, rpcUrl: 'http://x', confirmations: 1);
    final calldata = EscrowV2Calldata();
    const buyerAddr = '0x00000000000000000000000000000000000000b1';
    final now = DateTime.utc(2026, 1, 1);
    final deadline = now.millisecondsSinceEpoch ~/ 1000 + 3600;
    final ref = '0x${'ab' * 32}';

    late FakeWallet wallet;
    late FakeChain chain;
    late EscrowV2Service service;

    OrderInfo proposal({int status = OrderInfo.adjustmentProposed, String buyer = buyerAddr, int? deadlineAt}) => OrderInfo(
          status: status, buyer: buyer, seller: '0x000000000000000000000000000000000000005e',
          productAmount: BigInt.parse('100000000000000000000'), deliveryAmount: BigInt.parse('10000000000000000000'),
          proposedDelivery: BigInt.parse('25000000000000000000'), adjustmentDeadline: deadlineAt ?? deadline,
        );

    setUp(() {
      wallet = FakeWallet(buyerAddr);
      chain = FakeChain(balance: BigInt.parse('1000000000000000000000'), allowanceValue: BigInt.zero)..orderInfo = proposal();
      wallet.onSent = (tx) {
        if (tx.to == testTokenAddress) chain.allowanceValue = BigInt.parse('15000000000000000000');
        chain.receipts[tx.hash] = TxReceiptInfo(success: true, blockNumber: chain.head);
      };
      service = EscrowV2Service(config: config, sender: wallet, reader: chain, pollInterval: Duration.zero, clock: () => now);
    });

    test('accepting approves only the extra 15 USDT, then accepts', () async {
      await service.acceptDeliveryAdjustmentForOrder(ref);
      expect(wallet.sent.length, 2);
      expect(wallet.sent[0].to, testTokenAddress);
      expect(wallet.sent[0].data, calldata.approve(escrow, BigInt.parse('15000000000000000000')));
      expect(wallet.sent[1].to, escrow);
      expect(wallet.sent[1].data, calldata.acceptDeliveryAdjustment(ref));
    });

    test('nothing is sent when there is nothing to answer', () async {
      chain.orderInfo = proposal(status: OrderInfo.paid);
      await expectLater(service.acceptDeliveryAdjustmentForOrder(ref),
          throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'NO_PROPOSAL')));
      expect(wallet.sent, isEmpty);
    });
    test('nothing is sent when the order does not exist yet', () async {
      chain.orderInfo = null;
      await expectLater(service.acceptDeliveryAdjustmentForOrder(ref),
          throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'ORDER_NOT_FOUND')));
      expect(wallet.sent, isEmpty);
    });
    test('nothing is sent when the order belongs to another wallet', () async {
      chain.orderInfo = proposal(buyer: '0x00000000000000000000000000000000000000cc');
      await expectLater(service.acceptDeliveryAdjustmentForOrder(ref),
          throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'WRONG_WALLET')));
      expect(wallet.sent, isEmpty);
    });
    test('nothing is sent after the time to answer has passed', () async {
      chain.orderInfo = proposal(deadlineAt: deadline - 7200);
      await expectLater(service.acceptDeliveryAdjustmentForOrder(ref),
          throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'TOO_LATE')));
      expect(wallet.sent, isEmpty);
    });
    test('declining goes straight to the escrow', () async {
      await service.declineDeliveryAdjustment(ref);
      expect(wallet.sent.single.data, calldata.declineDeliveryAdjustment(ref));
    });
  });
}
