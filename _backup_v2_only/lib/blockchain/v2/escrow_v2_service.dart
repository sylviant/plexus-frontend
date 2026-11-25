import 'dart:async';
import 'dart:typed_data';

import 'escrow_v2_calldata.dart';
import 'escrow_v2_config.dart';
import 'escrow_v2_errors.dart';
import 'escrow_v2_models.dart';
import 'escrow_v2_ports.dart';

/// The payment and order actions of the V2 escrow, through the user's own wallet (task 2.1).
///
/// The app never holds a private key: every transaction is sent to the wallet through [TxSender], and the
/// user approves it there. All checks that can be made before the wallet is asked are made first.
class EscrowV2Service {
  EscrowV2Service({
    required this.config,
    required this.sender,
    required this.reader,
    EscrowV2Calldata? calldata,
    this.pollInterval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 3),
    DateTime Function()? clock,
  })  : calldata = calldata ?? EscrowV2Calldata(),
        _clock = clock ?? DateTime.now;

  final EscrowV2Config config;
  final TxSender sender;
  final ChainReader reader;
  final EscrowV2Calldata calldata;
  final Duration pollInterval;
  final Duration timeout;
  final DateTime Function() _clock;

  /// Pays a signed quote: checks, approves the token if needed, then creates the order. The user approves each
  /// step in the wallet. Throws an [EscrowException] with a message that can be shown as it is.
  Future<PayResult> pay(SignedQuote quote, {void Function(PayStep step)? onStep}) async {
    onStep?.call(PayStep.checking);
    final buyer = _connectedWallet();
    if (buyer.toLowerCase() != quote.buyer.toLowerCase()) {
      throw const EscrowException(
          'WRONG_WALLET', 'This order was made for a different wallet. Connect the wallet you ordered with.');
    }
    _requireFreshQuote(quote);

    final total = quote.total;
    final balance = await reader.tokenBalance(buyer);
    if (balance < total) {
      throw EscrowException('INSUFFICIENT_USDT',
          'Your wallet does not hold enough USDT for this order (needs ${_fmt(total)}, has ${_fmt(balance)}).');
    }

    String? approveTx;
    final allowance = await reader.allowance(buyer, config.escrowAddress);
    if (allowance < total) {
      onStep?.call(PayStep.approving);
      approveTx = await _send(config.tokenAddress, calldata.approve(config.escrowAddress, total));
      await _waitForAllowance(buyer, total);
      // Approving can take a while: the quote must still be good before the order is created.
      _requireFreshQuote(quote);
    }

    onStep?.call(PayStep.creatingOrder);
    final createTx = await _send(config.escrowAddress, calldata.createOrder(quote), confirmations: 0);
    onStep?.call(PayStep.confirming);
    await _waitForConfirmations(createTx, config.confirmations);
    onStep?.call(PayStep.done);
    return PayResult(approveTx: approveTx, createOrderTx: createTx);
  }

  // ---- buyer
  Future<String> confirmReceipt(String orderRef) => _act(calldata.confirmReceipt(orderRef));
  Future<String> openDispute(String orderRef, String reason) =>
      _act(calldata.openDispute(orderRef, EscrowV2Calldata.hashText(reason)));
  Future<String> withdrawDispute(String orderRef) => _act(calldata.withdrawDispute(orderRef));
  /// Accepting a higher delivery fee pays only the [extraAmount] difference into the same order. The escrow pulls
  /// it from the buyer's wallet, so the balance and the allowance are checked first and an approval is sent if needed.
  Future<String> acceptDeliveryAdjustment(String orderRef, {required BigInt extraAmount}) async {
    final buyer = _connectedWallet();
    final balance = await reader.tokenBalance(buyer);
    if (balance < extraAmount) {
      throw EscrowException('INSUFFICIENT_USDT',
          'Your wallet does not hold enough USDT for the extra delivery fee (needs ${_fmt(extraAmount)}, has ${_fmt(balance)}).');
    }
    if (await reader.allowance(buyer, config.escrowAddress) < extraAmount) {
      await _send(config.tokenAddress, calldata.approve(config.escrowAddress, extraAmount));
      await _waitForAllowance(buyer, extraAmount);
    }
    return _act(calldata.acceptDeliveryAdjustment(orderRef));
  }

  /// Accepts the seller's delivery fee change for this order: reads the order from the chain, checks that a change is
  /// really waiting for this wallet and that the time to answer has not passed, works out the extra amount, then
  /// approves it (if needed) and accepts. This is what a screen should call.
  Future<String> acceptDeliveryAdjustmentForOrder(String orderRef) async {
    final buyer = _connectedWallet();
    final o = await reader.order(orderRef);
    if (o == null) {
      throw const EscrowException('ORDER_NOT_FOUND', 'This order was not found on the blockchain yet. Wait a moment and try again.');
    }
    if (o.buyer.toLowerCase() != buyer.toLowerCase()) {
      throw const EscrowException('WRONG_WALLET', 'This order belongs to a different wallet.');
    }
    if (o.status != OrderInfo.adjustmentProposed) {
      throw const EscrowException('NO_PROPOSAL', 'There is no delivery fee change waiting for your answer.');
    }
    if (_clock().millisecondsSinceEpoch ~/ 1000 >= o.adjustmentDeadline) {
      throw const EscrowException('TOO_LATE', 'The time to answer this delivery fee change has passed.');
    }
    return acceptDeliveryAdjustment(orderRef, extraAmount: o.extraToPay);
  }

  Future<String> declineDeliveryAdjustment(String orderRef) => _act(calldata.declineDeliveryAdjustment(orderRef));

  // ---- seller
  Future<String> markShipped(String orderRef,
          {required String carrier, required String tracking, String proof = '', required int shippedAt}) =>
      _act(calldata.markShipped(orderRef, EscrowV2Calldata.hashText(carrier), EscrowV2Calldata.hashText(tracking),
          proof.isEmpty ? Uint8List(32) : EscrowV2Calldata.hashText(proof), shippedAt));
  Future<String> cancelBySeller(String orderRef) => _act(calldata.cancelBySeller(orderRef));
  Future<String> proposeDeliveryAdjustment(String orderRef, BigInt newDelivery, String reason) =>
      _act(calldata.proposeDeliveryAdjustment(orderRef, newDelivery, EscrowV2Calldata.hashText(reason)));

  // ---- withdrawals
  Future<String> withdraw() => _act(calldata.withdraw());
  Future<String> withdrawRefund() => _act(calldata.withdrawRefund());
  Future<String> withdrawRewards() => _act(calldata.withdrawRewards());

  // ---- internals
  String _connectedWallet() {
    final a = sender.address;
    if (!sender.isConnected || a == null) {
      throw const EscrowException('NOT_CONNECTED', 'Connect your wallet first.');
    }
    return a;
  }

  void _requireFreshQuote(SignedQuote q) {
    if (q.isExpired(now: _clock())) {
      throw const EscrowException('QUOTE_EXPIRED', 'This price quote has expired. Go back and request a new one.');
    }
  }

  /// One order action: sent to the escrow, waited for.
  Future<String> _act(String data) async {
    _connectedWallet();
    final tx = await _send(config.escrowAddress, data, confirmations: 0);
    await _waitForConfirmations(tx, config.confirmations);
    return tx;
  }

  /// Sends one transaction through the wallet and waits until it is mined (and [confirmations] blocks deep).
  Future<String> _send(String to, String data, {int confirmations = 1}) async {
    try {
      final hash = await sender.sendTransaction(to: to, data: data);
      if (confirmations > 0) await _waitForConfirmations(hash, confirmations);
      return hash;
    } catch (e) {
      throw interpretError(e);
    }
  }

  Future<void> _waitForConfirmations(String txHash, int confirmations) async {
    final deadline = _clock().add(timeout);
    while (true) {
      final r = await reader.receipt(txHash);
      if (r != null) {
        if (!r.success) {
          throw const EscrowException('TX_FAILED', 'The transaction was rejected by the network. Nothing was paid.');
        }
        final head = await reader.blockNumber();
        if (head - r.blockNumber + 1 >= confirmations) return;
      }
      if (!_clock().isBefore(deadline)) {
        throw const EscrowException(
            'TX_TIMEOUT', 'The network is slow. Check your wallet: the transaction may still go through.');
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// A node can lag a block behind the one that mined the approval, so wait until the allowance is visible.
  Future<void> _waitForAllowance(String owner, BigInt needed) async {
    final deadline = _clock().add(timeout);
    while (true) {
      if (await reader.allowance(owner, config.escrowAddress) >= needed) return;
      if (!_clock().isBefore(deadline)) {
        throw const EscrowException('TX_TIMEOUT', 'The approval is taking long to show up. Please try again.');
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  String _fmt(BigInt v) {
    // tokens have 18 decimals on BNB Smart Chain
    final s = v.toString().padLeft(19, '0');
    final whole = s.substring(0, s.length - 18);
    final frac = s.substring(s.length - 18).substring(0, 2);
    return '$whole.$frac USDT';
  }
}
