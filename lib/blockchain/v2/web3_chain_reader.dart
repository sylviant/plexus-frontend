import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import 'escrow_v2_abi.g.dart';
import 'escrow_v2_calldata.dart';
import 'escrow_v2_config.dart';
import 'escrow_v2_models.dart';
import 'escrow_v2_ports.dart';

/// Reads balances, allowances, orders and receipts from the BNB Smart Chain RPC. Read-only: it holds no key.
class Web3ChainReader implements ChainReader {
  Web3ChainReader(EscrowV2Config config, {http.Client? httpClient})
      : _client = Web3Client(config.effectiveRpcUrl, httpClient ?? http.Client()),
        _token = DeployedContract(
          ContractAbi.fromJson(erc20Abi, 'ERC20'),
          EthereumAddress.fromHex(config.tokenAddress),
        ),
        _escrow = DeployedContract(
          ContractAbi.fromJson(escrowV2Abi, 'PlexusEscrowV2'),
          EthereumAddress.fromHex(config.escrowAddress),
        );

  final Web3Client _client;
  final DeployedContract _token;
  final DeployedContract _escrow;

  @override
  Future<OrderInfo?> order(String orderRef) async {
    final r = await _client.call(
      contract: _escrow,
      function: _escrow.function('getOrder'),
      params: [EscrowV2Calldata.bytes32(orderRef)],
    );
    final info = OrderInfo.fromAbiResult(r.first as List<dynamic>);
    return info.status == 0 ? null : info; // status 0 means "no such order"
  }

  @override
  Future<BigInt> tokenBalance(String owner) async {
    final r = await _client.call(
      contract: _token,
      function: _token.function('balanceOf'),
      params: [EthereumAddress.fromHex(owner)],
    );
    return r.first as BigInt;
  }

  @override
  Future<BigInt> allowance(String owner, String spender) async {
    final r = await _client.call(
      contract: _token,
      function: _token.function('allowance'),
      params: [EthereumAddress.fromHex(owner), EthereumAddress.fromHex(spender)],
    );
    return r.first as BigInt;
  }

  @override
  Future<int> blockNumber() => _client.getBlockNumber();

  @override
  Future<TxReceiptInfo?> receipt(String txHash) async {
    final r = await _client.getTransactionReceipt(txHash);
    if (r == null) return null;
    return TxReceiptInfo(success: r.status ?? false, blockNumber: r.blockNumber.blockNum);
  }

  void dispose() => _client.dispose();
}
