import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'escrow_abi.dart';

class EscrowContract {
  // ⚠️ À remplacer par l'adresse réelle après déploiement BSC Testnet
  static const String contractAddress =
      '0x0000000000000000000000000000000000000000';

  static const String rpcUrl =
      'https://data-seed-prebsc-1-s1.binance.org:8545';

  late Web3Client _client;
  late DeployedContract _contract;

  EscrowContract() {
    _client = Web3Client(rpcUrl, http.Client());
    _contract = DeployedContract(
      ContractAbi.fromJson(escrowAbi, 'PlexusEscrow'),
      EthereumAddress.fromHex(contractAddress),
    );
  }

  // ── Lire les infos d'une commande ─────────────────────────────────────────
  Future<Map<String, dynamic>> getCommande(int id) async {
    final fonction = _contract.function('getCommande');
    final result = await _client.call(
      contract: _contract,
      function: fonction,
      params: [BigInt.from(id)],
    );

    return {
      'acheteur': result[0].toString(),
      'vendeur': result[1].toString(),
      'montant': result[2] as BigInt,
      'statut': (result[3] as BigInt).toInt(),
      'dateExpiration': result[4] as BigInt,
    };
  }

  // ── Créer une commande (payer) ─────────────────────────────────────────────
  Future<String> creerCommande({
    required String privateKey,
    required String adresseVendeur,
    required double montantBNB,
    int delaiJours = 7,
  }) async {
    final credentials = EthPrivateKey.fromHex(privateKey);
    final fonction = _contract.function('creerCommande');

    final txHash = await _client.sendTransaction(
      credentials,
      Transaction.callContract(
        contract: _contract,
        function: fonction,
        parameters: [
          EthereumAddress.fromHex(adresseVendeur),
          BigInt.from(delaiJours),
        ],
        value: EtherAmount.fromBigInt(
          EtherUnit.wei,
          BigInt.from(montantBNB * 1e18),
        ),
      ),
      chainId: 97, // BSC Testnet
    );

    return txHash;
  }

  // ── Confirmer la livraison ─────────────────────────────────────────────────
  Future<String> confirmerLivraison({
    required String privateKey,
    required int commandeId,
  }) async {
    final credentials = EthPrivateKey.fromHex(privateKey);
    final fonction = _contract.function('confirmerLivraison');

    final txHash = await _client.sendTransaction(
      credentials,
      Transaction.callContract(
        contract: _contract,
        function: fonction,
        parameters: [BigInt.from(commandeId)],
      ),
      chainId: 97,
    );

    return txHash;
  }

  // ── Ouvrir un litige ──────────────────────────────────────────────────────
  Future<String> ouvrirLitige({
    required String privateKey,
    required int commandeId,
  }) async {
    final credentials = EthPrivateKey.fromHex(privateKey);
    final fonction = _contract.function('ouvrirLitige');

    final txHash = await _client.sendTransaction(
      credentials,
      Transaction.callContract(
        contract: _contract,
        function: fonction,
        parameters: [BigInt.from(commandeId)],
      ),
      chainId: 97,
    );

    return txHash;
  }

  void dispose() => _client.dispose();
}