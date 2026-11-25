// Human readable signatures of PlexusEscrow.sol (repo: plexus-escrow)
export const METHODS = {
  creerCommande:
    'function creerCommande(address _vendeur, uint256 _delaiJours) payable returns (uint256)',
  confirmerLivraison: 'function confirmerLivraison(uint256 _id)',
  demanderRemboursement: 'function demanderRemboursement(uint256 _id)',
  ouvrirLitige: 'function ouvrirLitige(uint256 _id)',
} as const

export const EVENT_COMMANDE_CREEE =
  'event CommandeCreee(uint256 indexed id, address acheteur, address vendeur, uint256 montant)'

export type Action = 'pay' | 'confirm' | 'dispute' | 'refund'
