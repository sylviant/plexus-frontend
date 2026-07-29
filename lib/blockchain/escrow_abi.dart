const String escrowAbi = '''
[
  {
    "inputs": [{"name": "_platformFee", "type": "uint256"}],
    "stateMutability": "nonpayable",
    "type": "constructor"
  },
  {
    "name": "creerCommande",
    "type": "function",
    "stateMutability": "payable",
    "inputs": [
      {"name": "_vendeur", "type": "address"},
      {"name": "_delaiJours", "type": "uint256"}
    ],
    "outputs": [{"name": "", "type": "uint256"}]
  },
  {
    "name": "confirmerLivraison",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [{"name": "_id", "type": "uint256"}],
    "outputs": []
  },
  {
    "name": "demanderRemboursement",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [{"name": "_id", "type": "uint256"}],
    "outputs": []
  },
  {
    "name": "ouvrirLitige",
    "type": "function",
    "stateMutability": "nonpayable",
    "inputs": [{"name": "_id", "type": "uint256"}],
    "outputs": []
  },
  {
    "name": "getCommande",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{"name": "_id", "type": "uint256"}],
    "outputs": [
      {"name": "acheteur", "type": "address"},
      {"name": "vendeur", "type": "address"},
      {"name": "montant", "type": "uint256"},
      {"name": "statut", "type": "uint8"},
      {"name": "dateExpiration", "type": "uint256"}
    ]
  }
]
''';