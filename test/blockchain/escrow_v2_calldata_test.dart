import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/blockchain/v2/escrow_v2_calldata.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;

/// The golden file is produced by plexus-escrow/scripts/exportAppArtifacts.js with ethers.
/// If a test here fails, the app would send the contract a call it cannot decode.
void main() {
  final golden = jsonDecode(File('test/fixtures/escrow_v2_calldata.json').readAsStringSync()) as Map<String, dynamic>;
  final calls = golden['calls'] as Map<String, dynamic>;
  final escrow = golden['escrow'] as String;
  final signature = golden['signature'] as String;

  SignedQuote quoteFrom(Map<String, dynamic> j) => SignedQuote.fromJson({...j, 'signature': signature});
  final quote = quoteFrom(golden['quote'] as Map<String, dynamic>);
  final referred = quoteFrom(golden['quoteReferred'] as Map<String, dynamic>);
  final orderRef = quote.orderRef;
  final data = EscrowV2Calldata();
  final reasonHash = EscrowV2Calldata.hashText('reason');

  test('the golden file is the one for this contract', () {
    expect(calls.length, greaterThanOrEqualTo(20));
  });

  group('call data equals what ethers produces', () {
    test('token: approve', () {
      expect(data.approve(escrow, BigInt.parse('110000000000000000000')), calls['approve']);
      expect(data.approve(escrow, (BigInt.one << 256) - BigInt.one), calls['approveMax']);
    });
    test('createOrder, with and without a referrer, international or not', () {
      expect(data.createOrder(quote), calls['createOrder']);
      expect(data.createOrder(referred), calls['createOrderReferred']);
    });
    test('buyer actions', () {
      expect(data.confirmReceipt(orderRef), calls['confirmReceipt']);
      expect(data.openDispute(orderRef, reasonHash), calls['openDispute']);
      expect(data.withdrawDispute(orderRef), calls['withdrawDispute']);
      expect(data.acceptDeliveryAdjustment(orderRef), calls['acceptDeliveryAdjustment']);
      expect(data.declineDeliveryAdjustment(orderRef), calls['declineDeliveryAdjustment']);
      expect(
        data.markReturnShipped(orderRef, EscrowV2Calldata.hashText('DHL'), EscrowV2Calldata.hashText('RET'),
            EscrowV2Calldata.hashText('proof'), 1893400000),
        calls['markReturnShipped'],
      );
    });
    test('seller actions', () {
      expect(
        data.markShipped(orderRef, EscrowV2Calldata.hashText('DHL'), EscrowV2Calldata.hashText('TRACK'),
            EscrowV2Calldata.hashText('proof'), 1893400000),
        calls['markShipped'],
      );
      expect(data.cancelBySeller(orderRef), calls['cancelBySeller']);
      expect(data.proposeDeliveryAdjustment(orderRef, BigInt.parse('25000000000000000000'), reasonHash),
          calls['proposeDeliveryAdjustment']);
      expect(data.concedeDispute(orderRef), calls['concedeDispute']);
      expect(data.fundReturnPostage(orderRef), calls['fundReturnPostage']);
      expect(data.confirmReturnReceived(orderRef), calls['confirmReturnReceived']);
      expect(data.contestReturn(orderRef, reasonHash), calls['contestReturn']);
    });
    test('withdrawals', () {
      expect(data.withdraw(), calls['withdraw']);
      expect(data.withdrawRefund(), calls['withdrawRefund']);
      expect(data.withdrawRewards(), calls['withdrawRewards']);
    });
  });

  group('the signed quote', () {
    test('survives a JSON round trip', () {
      final again = SignedQuote.fromJson(jsonDecode(jsonEncode(quote.toJson())) as Map<String, dynamic>);
      expect(data.createOrder(again), data.createOrder(quote));
      expect(again.total, quote.productAmount + quote.deliveryAmount);
    });
    test('rejects malformed input', () {
      Map<String, dynamic> bad(String key, Object? value) => {...quote.toJson(), key: value};
      expect(() => SignedQuote.fromJson(bad('orderRef', '0x1234')), throwsFormatException);
      expect(() => SignedQuote.fromJson(bad('buyer', 'not an address')), throwsFormatException);
      expect(() => SignedQuote.fromJson(bad('signature', '0x${'ab' * 64}')), throwsFormatException);
      expect(() => SignedQuote.fromJson(bad('productAmount', '-5')), throwsFormatException);
      expect(() => SignedQuote.fromJson(bad('productAmount', '1.5')), throwsFormatException);
      expect(() => SignedQuote.fromJson(bad('feeBps', 20000)), throwsFormatException);
      expect(() => SignedQuote.fromJson(bad('international', 'yes')), throwsFormatException);
    });
    test('knows when it has expired, with a safety margin for approving and signing', () {
      final expires = quote.expiresAt;
      expect(quote.isExpired(now: expires.subtract(const Duration(minutes: 10))), isFalse);
      expect(quote.isExpired(now: expires.subtract(const Duration(seconds: 30))), isTrue); // inside the margin
      expect(quote.isExpired(now: expires.add(const Duration(seconds: 1))), isTrue);
    });
  });

  test('bytes32 refuses anything that is not 32 bytes', () {
    expect(() => EscrowV2Calldata.bytes32('0x1234'), throwsArgumentError);
    expect(EscrowV2Calldata.bytes32(orderRef), hexToBytes(orderRef));
  });
}
