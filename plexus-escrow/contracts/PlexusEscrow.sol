// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract PlexusEscrow {

    address public owner;
    uint256 public platformFee;  // Ex: 200 = 2% (base 10000)

    enum Status { EnAttente, Livre, Rembourse, Litige }

    struct Commande {
        address payable acheteur;
        address payable vendeur;
        uint256 montant;
        Status  statut;
        uint256 dateExpiration;
    }

    mapping(uint256 => Commande) public commandes;
    uint256 public nombreCommandes;

    event CommandeCreee(uint256 indexed id, address acheteur, address vendeur, uint256 montant);
    event LivraisonConfirmee(uint256 indexed id, uint256 montantVendeur, uint256 fraisPlexus);
    event Rembourse(uint256 indexed id);
    event LitigeOuvert(uint256 indexed id);
    event LitigeResolu(uint256 indexed id, address gagnant);

    modifier seulementOwner() {
        require(msg.sender == owner, "Acces refuse");
        _;
    }

    modifier commandeExiste(uint256 _id) {
        require(_id < nombreCommandes, "Commande inexistante");
        _;
    }

    constructor(uint256 _platformFee) {
        owner = msg.sender;
        platformFee = _platformFee;
    }

    // ── Acheteur paie et crée la commande ─────────────────────────────────────
    function creerCommande(address payable _vendeur, uint256 _delaiJours)
        external payable returns (uint256)
    {
        require(msg.value > 0, "Montant requis");
        require(_vendeur != address(0), "Adresse vendeur invalide");
        require(_vendeur != msg.sender, "Acheteur = vendeur interdit");

        uint256 id = nombreCommandes;
        commandes[id] = Commande({
            acheteur:       payable(msg.sender),
            vendeur:        _vendeur,
            montant:        msg.value,
            statut:         Status.EnAttente,
            dateExpiration: block.timestamp + (_delaiJours * 1 days)
        });
        nombreCommandes++;
        emit CommandeCreee(id, msg.sender, _vendeur, msg.value);
        return id;
    }

    // ── Acheteur confirme → vendeur reçoit son argent moins la commission ─────
    function confirmerLivraison(uint256 _id) external commandeExiste(_id) {
        Commande storage cmd = commandes[_id];
        require(msg.sender == cmd.acheteur, "Seul l'acheteur peut confirmer");
        require(cmd.statut == Status.EnAttente, "Commande non en attente");

        cmd.statut = Status.Livre;
        uint256 frais      = (cmd.montant * platformFee) / 10000;
        uint256 netVendeur = cmd.montant - frais;

        cmd.vendeur.transfer(netVendeur);
        if (frais > 0) payable(owner).transfer(frais); // ta commission PLEXUS

        emit LivraisonConfirmee(_id, netVendeur, frais);
    }

    // ── Remboursement si délai dépassé ────────────────────────────────────────
    function demanderRemboursement(uint256 _id) external commandeExiste(_id) {
        Commande storage cmd = commandes[_id];
        require(cmd.statut == Status.EnAttente, "Commande non en attente");
        require(msg.sender == cmd.acheteur || msg.sender == owner, "Non autorise");
        require(block.timestamp >= cmd.dateExpiration || msg.sender == owner, "Delai non expire");

        cmd.statut = Status.Rembourse;
        cmd.acheteur.transfer(cmd.montant);
        emit Rembourse(_id);
    }

    // ── Ouvrir un litige ──────────────────────────────────────────────────────
    function ouvrirLitige(uint256 _id) external commandeExiste(_id) {
        Commande storage cmd = commandes[_id];
        require(msg.sender == cmd.acheteur || msg.sender == cmd.vendeur, "Non autorise");
        require(cmd.statut == Status.EnAttente, "Commande non en attente");
        cmd.statut = Status.Litige;
        emit LitigeOuvert(_id);
    }

    // ── Résoudre un litige (toi seul) ─────────────────────────────────────────
    function resoldreLitige(uint256 _id, bool _acheteurGagne)
        external seulementOwner commandeExiste(_id)
    {
        Commande storage cmd = commandes[_id];
        require(cmd.statut == Status.Litige, "Pas en litige");

        if (_acheteurGagne) {
            cmd.statut = Status.Rembourse;
            cmd.acheteur.transfer(cmd.montant);
            emit LitigeResolu(_id, cmd.acheteur);
        } else {
            cmd.statut = Status.Livre;
            uint256 frais      = (cmd.montant * platformFee) / 10000;
            uint256 netVendeur = cmd.montant - frais;
            cmd.vendeur.transfer(netVendeur);
            if (frais > 0) payable(owner).transfer(frais);
            emit LitigeResolu(_id, cmd.vendeur);
        }
    }

    function getCommande(uint256 _id) external view commandeExiste(_id)
        returns (address, address, uint256, Status, uint256)
    {
        Commande storage cmd = commandes[_id];
        return (cmd.acheteur, cmd.vendeur, cmd.montant, cmd.statut, cmd.dateExpiration);
    }

    function changerFrais(uint256 _nouveauFrais) external seulementOwner {
        require(_nouveauFrais <= 1000, "Max 10%");
        platformFee = _nouveauFrais;
    }
}