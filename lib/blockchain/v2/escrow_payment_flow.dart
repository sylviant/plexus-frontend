import 'escrow_api.dart';
import 'escrow_v2_errors.dart';
import 'escrow_v2_models.dart';
import 'escrow_v2_service.dart';

/// The result of paying an order from the app.
class PaymentOutcome {
  const PaymentOutcome({required this.result, required this.serverNotified, required this.quote});

  final PayResult result;

  /// False when the payment went through on-chain but the server could not be told right away. The server's
  /// own listener finds the payment by its order number, so this is not an error the buyer must act on.
  final bool serverNotified;
  final SignedQuote quote;
}

/// The one call a payment screen makes: "pay this order".
///
///   final flow = EscrowPaymentFlow(service: escrowService, api: httpEscrowApi);
///   final outcome = await flow.payOrder(orderId, onStep: (s) => setState(() => _step = s));
///
/// 1. asks the backend for a signed quote (the price is the server's, never the app's)
/// 2. pays it through the user's wallet (approval, then the order), see [EscrowV2Service.pay]
/// 3. tells the backend the transaction hash (best effort)
class EscrowPaymentFlow {
  EscrowPaymentFlow({required this.service, required this.api});

  final EscrowV2Service service;
  final EscrowApi api;

  Future<PaymentOutcome> payOrder(String orderId, {void Function(PayStep step)? onStep}) async {
    onStep?.call(PayStep.checking);
    final SignedQuote quote;
    try {
      quote = await api.fetchQuote(orderId);
    } catch (e) {
      throw interpretError(e);
    }

    final result = await service.pay(quote, onStep: onStep);

    var notified = true;
    try {
      await api.reportPayment(orderId, result.createOrderTx);
    } catch (_) {
      notified = false; // the money is already in the escrow: never turn this into a payment error
    }
    return PaymentOutcome(result: result, serverNotified: notified, quote: quote);
  }
}
