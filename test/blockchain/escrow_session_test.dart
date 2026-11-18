import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/blockchain/v2/escrow_session.dart';

void main() {
  test('the on-chain order number is keccak256 of the order id text (same as ethers.id)', () {
    // ethers.id("abc") = keccak256(utf8("abc"))
    expect(EscrowSession.orderRefFor('abc'), '0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45');
  });

  test('the order number has 32 bytes and differs per order', () {
    final a = EscrowSession.orderRefFor('order-1');
    final b = EscrowSession.orderRefFor('order-2');
    expect(a.length, 66);
    expect(a, isNot(b));
  });
}
