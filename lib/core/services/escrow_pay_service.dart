import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:plexus/core/api_config.dart';

/// Actions available on the hosted escrow page (plexus-pay, Thirdweb).
enum EscrowAction { pay, confirm, dispute, refund }

/// Opens the hosted pay page (same wallet list on web and mobile, with direct
/// redirection to the wallet app) and reads the result from the backend.
///
/// The app never touches a private key or a wallet session: the pay page talks
/// to the wallet, the backend verifies the transaction on-chain, and the app
/// only reads the order status.
class EscrowPayService {
  /// Asks the backend for a short-lived session, then opens the pay page.
  static Future<void> open({
    required String orderId,
    required String token,
    EscrowAction action = EscrowAction.pay,
    String? deliveryAddress,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/escrow/orders/$orderId/session'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'action': action.name,
        if (deliveryAddress != null && deliveryAddress.isNotEmpty)
          'deliveryAddress': deliveryAddress,
        // Web: come back to the app. Mobile: custom scheme (optional deep link).
        'returnUrl': kIsWeb ? Uri.base.origin : 'plexus://orders',
      }),
    );

    final Map<String, dynamic> body =
    res.body.isNotEmpty ? json.decode(res.body) as Map<String, dynamic> : {};
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? body['msg'] ?? 'HTTP ${res.statusCode}');
    }

    final Uri uri = Uri.parse(body['url'] as String);
    final bool ok = await launchUrl(
      uri,
      // Mobile: system browser, so wallet deep links and universal links work.
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      // Web: same tab (a popup would be blocked after an async call).
      webOnlyWindowName: '_self',
    );
    if (!ok) throw Exception('Cannot open the payment page');
  }

  /// Reads an order (public route used all over the app).
  static Future<Map<String, dynamic>?> fetchOrder(String orderId) async {
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/orders/$orderId'));
      if (res.statusCode != 200) return null;
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// True when the order has an escrow payment recorded on-chain.
  static bool isPaid(Map<String, dynamic> order) {
    final id = order['escrowId']?.toString();
    return id != null && id.isNotEmpty && id != 'null';
  }

  /// Polls the order until [done] is true (or timeout / [shouldStop]).
  static Future<Map<String, dynamic>?> waitFor(
      String orderId,
      bool Function(Map<String, dynamic> order) done, {
        Duration every = const Duration(seconds: 4),
        Duration timeout = const Duration(minutes: 10),
        bool Function()? shouldStop,
      }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (shouldStop != null && shouldStop()) return null;
      final order = await fetchOrder(orderId);
      if (order != null && done(order)) return order;
      await Future.delayed(every);
    }
    return null;
  }
}
