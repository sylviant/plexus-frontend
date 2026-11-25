import 'escrow_v2_deployment.g.dart';

/// One place for the network and contract settings of the V2 escrow (task 2.3).
///
/// Defaults come from the last deployment (escrow_v2_deployment.g.dart, generated). Override at build time:
///   flutter run --dart-define=ESCROW_CHAIN_ID=97 --dart-define=ESCROW_ADDRESS=0x... --dart-define=ESCROW_TOKEN=0x...
class EscrowV2Config {
  const EscrowV2Config({
    this.chainId = const int.fromEnvironment('ESCROW_CHAIN_ID', defaultValue: deployedChainId),
    this.escrowAddress = const String.fromEnvironment('ESCROW_ADDRESS', defaultValue: deployedEscrowAddress),
    this.tokenAddress = const String.fromEnvironment('ESCROW_TOKEN', defaultValue: deployedTokenAddress),
    this.rpcUrl = const String.fromEnvironment('ESCROW_RPC_URL', defaultValue: ''),
    this.confirmations = const int.fromEnvironment('ESCROW_CONFIRMATIONS', defaultValue: 3),
  });

  final int chainId;
  final String escrowAddress;
  final String tokenAddress;
  final String rpcUrl;

  /// Blocks to wait after a transaction before the app treats it as final. The server waits for more (12).
  final int confirmations;

  /// CAIP-2 chain id used in the WalletConnect session, for example "eip155:97".
  String get caip2 => 'eip155:$chainId';

  String get effectiveRpcUrl {
    if (rpcUrl.isNotEmpty) return rpcUrl;
    switch (chainId) {
      case 97:
        return 'https://bsc-testnet-rpc.publicnode.com';
      case 56:
        return 'https://bsc-dataseed.bnbchain.org';
      default:
        throw StateError('No RPC for chain $chainId: set ESCROW_RPC_URL');
    }
  }

  String get chainName => chainId == 56 ? 'BNB Smart Chain' : chainId == 97 ? 'BNB Smart Chain Testnet' : 'chain $chainId';
}
