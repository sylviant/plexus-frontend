import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/blockchain/v2/escrow_api.dart';
import 'package:plexus/blockchain/v2/escrow_v2_calldata.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';

/// test/fixtures/dev_quote.json is a REAL quote signed by the operator key for the deployed testnet contract
/// (plexus-escrow: `OUT=... npm run quote:testnet`). It proves the app and the contract tooling agree end to end.
void main() {
  final fixture = jsonDecode(File('test/fixtures/dev_quote.json').readAsStringSync()) as Map<String, dynamic>;
  final quoteJson = fixture['quote'] as Map<String, dynamic>;

  test('the app reads the server-format quote', () {
    final q = SignedQuote.fromJson(quoteJson);
    expect(q.orderRef, quoteJson['orderRef']);
    expect(q.total, BigInt.parse('110000000000000000000'));
    expect(q.feeBps, 200);
    expect(q.isExpired(now: DateTime.utc(2029, 12, 1)), isFalse);
  });

  test('the app encodes exactly the createOrder call that ethers encoded for the same signed quote', () {
    final q = SignedQuote.fromJson(quoteJson);
    expect(EscrowV2Calldata().createOrder(q), fixture['createOrderCalldata']);
  });

  test('the development stand-in for the backend serves that same quote', () async {
    final api = DevQuoteApi(jsonEncode(quoteJson));
    final q = await api.fetchQuote('any-order');
    expect(EscrowV2Calldata().createOrder(q), fixture['createOrderCalldata']);
  });
}
