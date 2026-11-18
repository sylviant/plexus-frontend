import 'dart:convert';

import 'package:http/http.dart' as http;

import 'escrow_v2_errors.dart';
import 'escrow_v2_models.dart';

/// What the app needs from the PLEXUS backend to pay an order on the V2 escrow.
///
/// The backend endpoints are proposed here for the backend team to build (task 2.2):
///   POST {baseUrl}/escrow/orders/{orderId}/quote     login required. Returns the signed quote (see [SignedQuote]).
///   POST {baseUrl}/escrow/orders/{orderId}/payment   login required. Body {"txHash": "0x…"}. Optional: the server's
///                                                    own listener also finds the payment on-chain by its order number.
abstract class EscrowApi {
  Future<SignedQuote> fetchQuote(String orderId);

  /// Tells the server the order was paid. A failure here must never undo or hide a payment that went through.
  Future<void> reportPayment(String orderId, String txHash);
}

class HttpEscrowApi implements EscrowApi {
  HttpEscrowApi({required this.baseUrl, required this.authToken, http.Client? client}) : _client = client ?? http.Client();

  /// For example "https://…/api" (the app's ApiConfig.baseUrl).
  final String baseUrl;

  /// The logged-in user's token, or null when logged out.
  final Future<String?> Function() authToken;
  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final t = await authToken();
    if (t == null || t.isEmpty) throw const EscrowException('NOT_LOGGED_IN', 'Please log in again.');
    return {'Content-Type': 'application/json', 'Authorization': 'Bearer $t'};
  }

  @override
  Future<SignedQuote> fetchQuote(String orderId) async {
    final res = await _client.post(Uri.parse('$baseUrl/escrow/orders/$orderId/quote'), headers: await _headers());
    final body = _decode(res);
    if (res.statusCode != 200) throw _serverError(res.statusCode, body);
    try {
      return SignedQuote.fromJson((body['quote'] ?? body) as Map<String, dynamic>);
    } on FormatException catch (e) {
      throw EscrowException('BAD_QUOTE', 'The server sent an invalid price quote. Please try again.', cause: e);
    }
  }

  @override
  Future<void> reportPayment(String orderId, String txHash) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/escrow/orders/$orderId/payment'),
      headers: await _headers(),
      body: jsonEncode({'txHash': txHash}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) throw _serverError(res.statusCode, _decode(res));
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final d = jsonDecode(res.body);
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  EscrowException _serverError(int status, Map<String, dynamic> body) {
    final text = (body['msg'] ?? body['message'] ?? body['error'])?.toString();
    if (status == 401) return const EscrowException('NOT_LOGGED_IN', 'Please log in again.');
    if (status == 403) return const EscrowException('FORBIDDEN', 'You are not allowed to pay this order.');
    if (status == 404) return const EscrowException('ORDER_NOT_FOUND', 'This order was not found.');
    return EscrowException('SERVER_ERROR', text ?? 'The server could not prepare this payment. Please try again.');
  }
}

/// Stand-in for the backend while the quote endpoint does not exist: uses a quote signed by hand
/// (plexus-escrow: `npm run quote:testnet`, which prints the JSON). Development and testing only.
///   flutter run --dart-define=DEV_QUOTE_JSON='{"orderRef":"0x…", …}'
class DevQuoteApi implements EscrowApi {
  DevQuoteApi(String quoteJson) : _quote = SignedQuote.fromJson(jsonDecode(quoteJson) as Map<String, dynamic>);
  final SignedQuote _quote;

  @override
  Future<SignedQuote> fetchQuote(String orderId) async => _quote;

  @override
  Future<void> reportPayment(String orderId, String txHash) async {}
}
