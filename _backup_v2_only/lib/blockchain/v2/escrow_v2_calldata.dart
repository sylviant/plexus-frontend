import 'dart:typed_data';

import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes, keccakUtf8;
import 'package:web3dart/web3dart.dart';

import 'escrow_v2_abi.g.dart';
import 'escrow_v2_models.dart';

/// Builds the call data for every contract call the app makes. Pure functions: no network, no keys.
/// The unit tests compare every result byte for byte with the call data produced by the contract tooling.
class EscrowV2Calldata {
  EscrowV2Calldata()
      : _escrow = ContractAbi.fromJson(escrowV2Abi, 'PlexusEscrowV2'),
        _erc20 = ContractAbi.fromJson(erc20Abi, 'ERC20');

  final ContractAbi _escrow;
  final ContractAbi _erc20;

  String _encode(ContractAbi abi, String fn, List<dynamic> params) {
    final f = abi.functions.firstWhere((x) => x.name == fn, orElse: () => throw ArgumentError('Unknown function $fn'));
    return '0x${bytesToHex(f.encodeCall(params))}';
  }

  static Uint8List bytes32(String hex) {
    final b = hexToBytes(hex);
    if (b.length != 32) throw ArgumentError('Expected 32 bytes, got ${b.length}');
    return Uint8List.fromList(b);
  }

  /// keccak256 of a text (used for reasons and tracking numbers: only the hash goes on-chain).
  static Uint8List hashText(String text) => keccakUtf8(text);

  // ---- token
  String approve(String spender, BigInt amount) => _encode(_erc20, 'approve', [EthereumAddress.fromHex(spender), amount]);

  // ---- buyer
  String createOrder(SignedQuote q) => _encode(_escrow, 'createOrder', [q.toAbiTuple(), q.signatureBytes]);
  String confirmReceipt(String orderRef) => _encode(_escrow, 'confirmReceipt', [bytes32(orderRef)]);
  String openDispute(String orderRef, Uint8List reasonHash) => _encode(_escrow, 'openDispute', [bytes32(orderRef), reasonHash]);
  String withdrawDispute(String orderRef) => _encode(_escrow, 'withdrawDispute', [bytes32(orderRef)]);
  String acceptDeliveryAdjustment(String orderRef) => _encode(_escrow, 'acceptDeliveryAdjustment', [bytes32(orderRef)]);
  String declineDeliveryAdjustment(String orderRef) => _encode(_escrow, 'declineDeliveryAdjustment', [bytes32(orderRef)]);
  String markReturnShipped(String orderRef, Uint8List carrier, Uint8List tracking, Uint8List proof, int shippedAt) =>
      _encode(_escrow, 'markReturnShipped', [bytes32(orderRef), carrier, tracking, proof, BigInt.from(shippedAt)]);

  // ---- seller
  String markShipped(String orderRef, Uint8List carrier, Uint8List tracking, Uint8List proof, int shippedAt) =>
      _encode(_escrow, 'markShipped', [bytes32(orderRef), carrier, tracking, proof, BigInt.from(shippedAt)]);
  String cancelBySeller(String orderRef) => _encode(_escrow, 'cancelBySeller', [bytes32(orderRef)]);
  String proposeDeliveryAdjustment(String orderRef, BigInt newDelivery, Uint8List reasonHash) =>
      _encode(_escrow, 'proposeDeliveryAdjustment', [bytes32(orderRef), newDelivery, reasonHash]);
  String concedeDispute(String orderRef) => _encode(_escrow, 'concedeDispute', [bytes32(orderRef)]);
  String fundReturnPostage(String orderRef) => _encode(_escrow, 'fundReturnPostage', [bytes32(orderRef)]);
  String confirmReturnReceived(String orderRef) => _encode(_escrow, 'confirmReturnReceived', [bytes32(orderRef)]);
  String contestReturn(String orderRef, Uint8List reasonHash) => _encode(_escrow, 'contestReturn', [bytes32(orderRef), reasonHash]);

  // ---- anyone with a balance
  String withdraw() => _encode(_escrow, 'withdraw', const []);
  String withdrawRefund() => _encode(_escrow, 'withdrawRefund', const []);
  String withdrawRewards() => _encode(_escrow, 'withdrawRewards', const []);
}
