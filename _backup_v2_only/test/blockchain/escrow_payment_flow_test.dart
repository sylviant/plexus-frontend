import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexus/blockchain/v2/escrow_api.dart';
import 'package:plexus/blockchain/v2/escrow_payment_flow.dart';
import 'package:plexus/blockchain/v2/escrow_v2_calldata.dart';
import 'package:plexus/blockchain/v2/escrow_v2_config.dart';
import 'package:plexus/blockchain/v2/escrow_v2_errors.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';
import 'package:plexus/blockchain/v2/escrow_v2_ports.dart';
import 'package:plexus/blockchain/v2/escrow_v2_service.dart';

import 'fakes.dart';

class _FakeApi implements EscrowApi {
  _FakeApi(this.quote);
  final SignedQuote quote;
  Object? failQuote;
  Object? failReport;
  final reported = <String>[];

  @override
  Future<SignedQuote> fetchQuote(String orderId) async {
    if (failQuote != null) throw failQuote!;
    return quote;
  }

  @override
  Future<void> reportPayment(String orderId, String txHash) async {
    if (failReport != null) throw failReport!;
    reported.add('$orderId:$txHash');
  }
}

void main() {
  final golden = jsonDecode(File('test/fixtures/escrow_v2_calldata.json').readAsStringSync()) as Map<String, dynamic>;
  final escrow = golden['escrow'] as String;
  final quote = SignedQuote.fromJson({...(golden['quote'] as Map<String, dynamic>), 'signature': golden['signature']});
  final config = EscrowV2Config(chainId: 97, escrowAddress: escrow, tokenAddress: testTokenAddress, rpcUrl: 'http://x', confirmations: 2);

  late FakeWallet wallet;
  late FakeChain chain;
  late EscrowV2Service service;

  setUp(() {
    wallet = FakeWallet(quote.buyer);
    chain = FakeChain(balance: quote.total * BigInt.from(2), allowanceValue: quote.total);
    wallet.onSent = (tx) => chain.receipts[tx.hash] = TxReceiptInfo(success: true, blockNumber: chain.head);
    service = EscrowV2Service(
      config: config, sender: wallet, reader: chain, pollInterval: Duration.zero,
      clock: () => DateTime.utc(2029, 12, 31),
    );
  });

  group('paying an order', () {
    test('gets the price from the server, pays it through the wallet and tells the server', () async {
      final api = _FakeApi(quote);
      final steps = <PayStep>[];
      final outcome = await EscrowPaymentFlow(service: service, api: api).payOrder('order-42', onStep: steps.add);

      expect(wallet.sent.single.data, EscrowV2Calldata().createOrder(quote)); // exactly the server's quote
      expect(api.reported, ['order-42:${wallet.sent.single.hash}']);
      expect(outcome.serverNotified, isTrue);
      expect(outcome.quote.orderRef, quote.orderRef);
      expect(steps.first, PayStep.checking);
      expect(steps.last, PayStep.done);
    });

    test('a payment that went through is never reported as failed because the server did not answer', () async {
      final api = _FakeApi(quote)..failReport = Exception('server down');
      final outcome = await EscrowPaymentFlow(service: service, api: api).payOrder('order-42');
      expect(outcome.serverNotified, isFalse);
      expect(outcome.result.createOrderTx, wallet.sent.single.hash);
    });

    test('if the server cannot give a quote the wallet is never asked', () async {
      final api = _FakeApi(quote)..failQuote = const EscrowException('NOT_LOGGED_IN', 'Please log in again.');
      await expectLater(EscrowPaymentFlow(service: service, api: api).payOrder('order-42'),
          throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'NOT_LOGGED_IN')));
      expect(wallet.sent, isEmpty);
    });

    test('a user who rejects in the wallet pays nothing and the server is not told', () async {
      wallet.rejectRequestNumber = 0;
      final api = _FakeApi(quote);
      await expectLater(EscrowPaymentFlow(service: service, api: api).payOrder('order-42'),
          throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'USER_REJECTED')));
      expect(api.reported, isEmpty);
    });
  });

  group('the backend client', () {
    final quoteJson = jsonEncode({'quote': quote.toJson()});

    HttpEscrowApi apiWith(Future<http.Response> Function(http.Request) handler, {String? token = 'jwt-123'}) =>
        HttpEscrowApi(baseUrl: 'https://api.test/api', authToken: () async => token, client: MockClient(handler));

    test('asks for the quote of the right order, as the logged-in user', () async {
      late http.Request seen;
      final api = apiWith((req) async {
        seen = req;
        return http.Response(quoteJson, 200);
      });
      final q = await api.fetchQuote('order-42');
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.test/api/escrow/orders/order-42/quote');
      expect(seen.headers['Authorization'], 'Bearer jwt-123');
      expect(q.orderRef, quote.orderRef);
      expect(q.total, quote.total);
    });

    test('accepts the quote at the top level of the answer too', () async {
      final api = apiWith((req) async => http.Response(jsonEncode(quote.toJson()), 200));
      expect((await api.fetchQuote('o')).orderRef, quote.orderRef);
    });

    test('sends the transaction hash when reporting the payment', () async {
      late http.Request seen;
      final api = apiWith((req) async {
        seen = req;
        return http.Response('{}', 200);
      });
      await api.reportPayment('order-42', '0xabc');
      expect(seen.url.path, '/api/escrow/orders/order-42/payment');
      expect(jsonDecode(seen.body), {'txHash': '0xabc'});
    });

    test('turns server answers into readable errors', () async {
      Future<void> expectCode(int status, String body, String code) => expectLater(
          apiWith((req) async => http.Response(body, status)).fetchQuote('o'),
          throwsA(isA<EscrowException>().having((e) => e.code, 'code', code)));
      await expectCode(401, '{}', 'NOT_LOGGED_IN');
      await expectCode(403, '{}', 'FORBIDDEN');
      await expectCode(404, '{}', 'ORDER_NOT_FOUND');
      await expectCode(500, '{"msg":"Seller wallet missing"}', 'SERVER_ERROR');
      await expectCode(200, '{"quote":{"orderRef":"0x12"}}', 'BAD_QUOTE'); // the server sent something unusable
      await expectCode(200, 'not json', 'BAD_QUOTE');
    });

    test('a logged-out user is asked to log in before anything is sent', () async {
      var called = false;
      final api = apiWith((req) async {
        called = true;
        return http.Response(quoteJson, 200);
      }, token: null);
      await expectLater(api.fetchQuote('o'), throwsA(isA<EscrowException>().having((e) => e.code, 'code', 'NOT_LOGGED_IN')));
      expect(called, isFalse);
    });
  });

  test('the development stand-in hands back the quote it was given', () async {
    final api = DevQuoteApi(jsonEncode(quote.toJson()));
    expect((await api.fetchQuote('anything')).orderRef, quote.orderRef);
    await api.reportPayment('anything', '0x1'); // does nothing, does not fail
  });
}
