import 'escrow_v2_abi.g.dart';

/// An error with a code the app can react to and a message that is safe to show to a user.
class EscrowException implements Exception {
  const EscrowException(this.code, this.message, {this.cause});

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Readable text for the contract's custom errors (the keys are the error names in the contract).
const Map<String, String> _friendlyContractErrors = {
  'QuoteExpired': 'This price quote has expired. Go back and request a new one.',
  'BadSignature': 'The price quote could not be verified. Request a new one.',
  'FeeMismatch': 'The fee changed since this quote was made. Request a new one.',
  'OrderExists': 'This order has already been paid.',
  'OrderNotFound': 'This order was not found on the blockchain yet. Wait a moment and try again.',
  'InvalidSeller': 'The seller of this order is not valid.',
  'InvalidAmount': 'The amount is not valid.',
  'InvalidReferrer': 'The referral code cannot be used for this order.',
  'ReferrerMismatch': 'This account is already linked to a different referral code.',
  'NotBuyer': 'Only the buyer can do this.',
  'NotSeller': 'Only the seller can do this.',
  'NotOperator': 'This action is reserved for the PLEXUS server.',
  'WrongStatus': 'This order is not in the right state for that action.',
  'TooEarly': 'It is too early for this action.',
  'TooLate': 'The time limit for this action has passed.',
  'AdjustmentAlreadyUsed': 'The delivery fee was already changed once on this order.',
  'TransferMismatch': 'The token transfer was not accepted.',
  'NothingToWithdraw': 'There is nothing to withdraw.',
  'NotVerified': 'Complete the identity check before withdrawing rewards.',
  'BelowMinimum': 'The balance is below the minimum withdrawal.',
  'InvalidShipment': 'The shipping details are not valid.',
  'EnforcedPause': 'New orders are temporarily paused.',
};

final RegExp _selector = RegExp(r'0x[0-9a-fA-F]{8}(?![0-9a-fA-F])');

/// Finds a contract error name in any error text: a 4-byte revert selector or the error name itself.
String? contractErrorName(String text) {
  for (final m in _selector.allMatches(text)) {
    final name = escrowV2ErrorNames[m.group(0)!.toLowerCase()];
    if (name != null) return name;
  }
  for (final name in _friendlyContractErrors.keys) {
    if (text.contains(name)) return name;
  }
  return null;
}

/// Turns anything thrown by the wallet, the network or the contract into an [EscrowException].
EscrowException interpretError(Object error) {
  if (error is EscrowException) return error;
  final text = error.toString();
  final name = contractErrorName(text);
  if (name != null) {
    return EscrowException(name, _friendlyContractErrors[name] ?? 'The contract refused this action ($name).', cause: error);
  }
  final lower = text.toLowerCase();
  if (lower.contains('insufficient funds') || lower.contains('insufficient balance for transfer')) {
    return EscrowException('INSUFFICIENT_GAS', 'Not enough BNB in your wallet to pay the network fee.', cause: error);
  }
  if (lower.contains('user rejected') || lower.contains('user denied') || lower.contains('rejected')) {
    return EscrowException('USER_REJECTED', 'You rejected the request in your wallet. Nothing was paid.', cause: error);
  }
  return EscrowException('UNKNOWN', 'Something went wrong. Please try again.', cause: error);
}
