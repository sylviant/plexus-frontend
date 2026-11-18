import 'dart:typed_data';

import 'package:web3dart/crypto.dart' show hexToBytes;
import 'package:web3dart/web3dart.dart';

/// A purchase quote signed by the PLEXUS server (operator key), exactly as the contract's createOrder expects it.
///
/// JSON shape the backend returns (amounts are whole numbers in the token's smallest unit, as strings):
/// ```json
/// { "orderRef": "0x…32 bytes", "buyer": "0x…", "seller": "0x…", "referrer": "0x0000…0000",
///   "productAmount": "100000000000000000000", "deliveryAmount": "10000000000000000000",
///   "feeBps": 200, "international": false, "validUntil": 1893456000, "signature": "0x…65 bytes" }
/// ```
class SignedQuote {
  const SignedQuote({
    required this.orderRef,
    required this.buyer,
    required this.seller,
    required this.referrer,
    required this.productAmount,
    required this.deliveryAmount,
    required this.feeBps,
    required this.international,
    required this.validUntil,
    required this.signature,
  });

  final String orderRef;
  final String buyer;
  final String seller;
  final String referrer;
  final BigInt productAmount;
  final BigInt deliveryAmount;
  final int feeBps;
  final bool international;

  /// Unix time in seconds.
  final int validUntil;
  final String signature;

  /// What the buyer pays: product plus delivery, shown separately in the app.
  BigInt get total => productAmount + deliveryAmount;

  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch(validUntil * 1000, isUtc: true);

  /// True when the quote can no longer be used, or will expire within [margin] (time to approve and sign).
  bool isExpired({DateTime? now, Duration margin = const Duration(seconds: 60)}) {
    final t = (now ?? DateTime.now()).toUtc();
    return !t.add(margin).isBefore(expiresAt);
  }

  factory SignedQuote.fromJson(Map<String, dynamic> j) {
    String hex(String key, int bytes) {
      final v = j[key];
      if (v is! String || !RegExp('^0x[0-9a-fA-F]{${bytes * 2}}\$').hasMatch(v)) {
        throw FormatException('Invalid quote: "$key" must be $bytes bytes of hex');
      }
      return v;
    }

    String address(String key) {
      final v = hex(key, 20);
      EthereumAddress.fromHex(v); // throws on a malformed address
      return v;
    }

    BigInt amount(String key) {
      final v = j[key];
      final parsed = v is String ? BigInt.tryParse(v) : (v is int ? BigInt.from(v) : null);
      if (parsed == null || parsed.isNegative) throw FormatException('Invalid quote: "$key" must be a whole number');
      return parsed;
    }

    final feeBps = j['feeBps'];
    final validUntil = j['validUntil'];
    if (feeBps is! int || feeBps < 0 || feeBps > 10000) throw const FormatException('Invalid quote: "feeBps"');
    if (validUntil is! int || validUntil <= 0) throw const FormatException('Invalid quote: "validUntil"');
    if (j['international'] is! bool) throw const FormatException('Invalid quote: "international"');

    return SignedQuote(
      orderRef: hex('orderRef', 32),
      buyer: address('buyer'),
      seller: address('seller'),
      referrer: address('referrer'),
      productAmount: amount('productAmount'),
      deliveryAmount: amount('deliveryAmount'),
      feeBps: feeBps,
      international: j['international'] as bool,
      validUntil: validUntil,
      signature: hex('signature', 65),
    );
  }

  Map<String, dynamic> toJson() => {
        'orderRef': orderRef,
        'buyer': buyer,
        'seller': seller,
        'referrer': referrer,
        'productAmount': productAmount.toString(),
        'deliveryAmount': deliveryAmount.toString(),
        'feeBps': feeBps,
        'international': international,
        'validUntil': validUntil,
        'signature': signature,
      };

  /// The Quote struct as the ABI encoder wants it: values in the contract's field order.
  List<dynamic> toAbiTuple() => [
        Uint8List.fromList(hexToBytes(orderRef)),
        EthereumAddress.fromHex(buyer),
        EthereumAddress.fromHex(seller),
        EthereumAddress.fromHex(referrer),
        productAmount,
        deliveryAmount,
        BigInt.from(feeBps),
        international,
        BigInt.from(validUntil),
      ];

  Uint8List get signatureBytes => Uint8List.fromList(hexToBytes(signature));
}

/// The part of an on-chain order the app needs to decide what the user can do next.
class OrderInfo {
  const OrderInfo({
    required this.status,
    required this.buyer,
    required this.seller,
    required this.productAmount,
    required this.deliveryAmount,
    required this.proposedDelivery,
    required this.adjustmentDeadline,
  });

  /// Contract status codes (the Status enum in PlexusEscrowV2).
  static const int paid = 1, adjustmentProposed = 2, shipped = 3, disputed = 4, completed = 5, refunded = 6;
  static const List<String> statusNames = [
    'None', 'Paid', 'Delivery change proposed', 'Shipped', 'Disputed', 'Completed', 'Refunded', 'Return approved', 'Return shipped',
  ];

  final int status;
  final String buyer;
  final String seller;
  final BigInt productAmount;
  final BigInt deliveryAmount;

  /// The seller's proposed new delivery fee while a change is waiting for the buyer.
  final BigInt proposedDelivery;

  /// Unix time (seconds) until which the buyer can answer a delivery change.
  final int adjustmentDeadline;

  String get statusName => status >= 0 && status < statusNames.length ? statusNames[status] : 'Unknown ($status)';

  /// What the buyer would pay on top of what is already held if the proposal is accepted.
  BigInt get extraToPay => proposedDelivery > deliveryAmount ? proposedDelivery - deliveryAmount : BigInt.zero;

  /// Builds it from the decoded `getOrder` result. The positions are the fields of the contract's Order struct.
  factory OrderInfo.fromAbiResult(List<dynamic> t) => OrderInfo(
        buyer: (t[0] as EthereumAddress).hexEip55,
        seller: (t[1] as EthereumAddress).hexEip55,
        productAmount: t[3] as BigInt,
        deliveryAmount: t[4] as BigInt,
        proposedDelivery: t[5] as BigInt,
        status: (t[10] as BigInt).toInt(),
        adjustmentDeadline: (t[20] as BigInt).toInt(),
      );
}

/// Result of a payment: the approval (when one was needed) and the order creation.
class PayResult {
  const PayResult({required this.createOrderTx, this.approveTx});
  final String? approveTx;
  final String createOrderTx;
}

/// Progress of [EscrowV2Service.pay], for the payment screen.
enum PayStep { checking, approving, creatingOrder, confirming, done }
