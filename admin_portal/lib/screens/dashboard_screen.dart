import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../admin_config.dart';
import 'package:image_picker/image_picker.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int     _selectedIndex = 0;
  bool    _isLoading     = true;
  String  _debugMessage  = "Initialisation...";
  String? _adminToken;

  List<dynamic> _orders        = [];
  List<dynamic> _disputes      = [];
  List<dynamic> _pendingSellers = [];
  List<dynamic> _allUsers      = [];
  List<dynamic> _categories    = [];
  List<dynamic> _allProducts   = [];
  List<dynamic> _promoCodes    = [];   // NOUVEAU

  @override
  void initState() {
    super.initState();
    _loadTokenAndFetch();
  }

  Future<void> _loadTokenAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _adminToken = prefs.getString('admin_token');
    if (_adminToken == null || _adminToken!.isEmpty) { _logout(); return; }
    _fetchData();
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_token');
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_adminToken',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _debugMessage = "Synchronisation Northflank..."; });

    try {
      final usersRes = await http.get(Uri.parse('${AdminConfig.baseUrl}/users'), headers: _headers);
      if (usersRes.statusCode == 200) {
        final results = await Future.wait([
          http.get(Uri.parse('${AdminConfig.baseUrl}/orders'),      headers: _headers),
          http.get(Uri.parse('${AdminConfig.baseUrl}/disputes'),    headers: _headers),
          http.get(Uri.parse('${AdminConfig.baseUrl}/categories'),  headers: _headers),
          http.get(Uri.parse('${AdminConfig.baseUrl}/products'),    headers: _headers),
          http.get(Uri.parse('${AdminConfig.baseUrl}/admin/promo'), headers: _headers), // NOUVEAU
        ]);

        if (mounted) setState(() {
          _allUsers      = json.decode(usersRes.body);
          _orders        = json.decode(results[0].body);
          if (results[1].statusCode == 200) _disputes   = json.decode(results[1].body);
          if (results[2].statusCode == 200) _categories = json.decode(results[2].body);
          if (results[3].statusCode == 200) {
            final d = json.decode(results[3].body);
            _allProducts = d['products'] ?? [];
          }
          if (results[4].statusCode == 200) _promoCodes = json.decode(results[4].body); // NOUVEAU
          _pendingSellers = _allUsers.where((u) => u['role'] == 'seller' && u['isApproved'] != true).toList();
          _debugMessage   = "Administrateur Connecté";
          _isLoading      = false;
        });
      } else {
        setState(() { _debugMessage = "Erreur session"; _isLoading = false; });
        if (usersRes.statusCode == 401) _logout();
      }
    } catch (e) {
      if (mounted) setState(() { _debugMessage = "Erreur: $e"; _isLoading = false; });
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────
  Future<void> _validateOrder(String orderId) async {
    try {
      final res = await http.put(Uri.parse('${AdminConfig.baseUrl}/admin/orders/$orderId/validate'), headers: _headers);
      if (res.statusCode == 200) {
        _fetchData();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Paiement validé ! Vendeur notifié."), backgroundColor: Colors.green));
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _approveSeller(String userId) async {
    try {
      final res = await http.put(Uri.parse('${AdminConfig.baseUrl}/admin/approve-seller/$userId'), headers: _headers);
      if (res.statusCode == 200) _fetchData();
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _resolveDispute(String id, String action) async {
    try {
      final res = await http.post(Uri.parse('${AdminConfig.baseUrl}/admin/disputes/$id/resolve'), headers: _headers, body: json.encode({'action': action}));
      if (res.statusCode == 200) _fetchData();
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _deleteItem(String type, String id) async {
    try {
      final res = await http.delete(Uri.parse('${AdminConfig.baseUrl}/$type/$id'), headers: _headers);
      if (res.statusCode == 200) _fetchData();
    } catch (e) { debugPrint(e.toString()); }
  }

  // NOUVEAU : Basculer actif/inactif d'un code promo
  Future<void> _togglePromo(String id, bool currentStatus) async {
    try {
      await http.put(
        Uri.parse('${AdminConfig.baseUrl}/admin/promo/$id'),
        headers: _headers,
        body: json.encode({'isActive': !currentStatus}),
      );
      _fetchData();
    } catch (e) { debugPrint(e.toString()); }
  }

  // NOUVEAU : Supprimer un code promo
  Future<void> _deletePromo(String id) async {
    try {
      await http.delete(Uri.parse('${AdminConfig.baseUrl}/admin/promo/$id'), headers: _headers);
      _fetchData();
    } catch (e) { debugPrint(e.toString()); }
  }

  // NOUVEAU : Créer un code promo
  Future<void> _createPromo(String code, double discount, String? expiresAt, int? maxUsage) async {
    try {
      final body = <String, dynamic>{'code': code, 'discount': discount};
      if (expiresAt != null && expiresAt.isNotEmpty) body['expiresAt'] = expiresAt;
      if (maxUsage != null) body['maxUsage'] = maxUsage;

      final res = await http.post(
        Uri.parse('${AdminConfig.baseUrl}/admin/promo'),
        headers: _headers,
        body: json.encode(body),
      );

      if (res.statusCode == 201) {
        _fetchData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Code "$code" créé avec succès !'), backgroundColor: Colors.green),
        );
      } else {
        final msg = json.decode(res.body)['msg'] ?? 'Erreur création.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: Row(children: [
        _buildSidebar(),
        Expanded(child: Column(children: [
          _buildTopbar(),
          _buildStatusBar(),
          Expanded(child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
              : SingleChildScrollView(padding: const EdgeInsets.all(30), child: _buildMainContent())),
        ])),
      ]),
    );
  }

  Widget _buildStatusBar() => Container(
    width: double.infinity, color: const Color(0xFF1A237E),
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
    child: Text("PLEXUS SECURITY : $_debugMessage", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
  );

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0: return _buildDashboardView();
      case 1: return _buildSellersView();
      case 2: return _buildProductsView();
      case 3: return _buildCategoriesView();
      case 4: return _buildUsersView();
      case 5: return _buildDisputesView();
      case 6: return _buildOrdersView();
      case 7: return _buildPromoView();   // NOUVEAU
      default: return _buildDashboardView();
    }
  }

  // ─── Dashboard ────────────────────────────────────────────────────────────
  Widget _buildDashboardView() {
    double total = _orders.fold(0, (sum, o) => sum + (double.tryParse(o['totalAmount']?.toString() ?? '0') ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Tableau de Bord Central", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
      const SizedBox(height: 25),
      Row(children: [
        _buildStatBox("Volume Escrow",    "\$${total.toStringAsFixed(2)}",                               Icons.account_balance_wallet, Colors.blue),
        const SizedBox(width: 20),
        _buildStatBox("À valider",        "${_orders.where((o) => o['status'] == 'PENDING_ADMIN').length}", Icons.notification_important, Colors.orange),
        const SizedBox(width: 20),
        _buildStatBox("Produits Live",    "${_allProducts.length}",                                      Icons.inventory_2_rounded,    Colors.teal),
        const SizedBox(width: 20),
        _buildStatBox("Codes Promo",      "${_promoCodes.where((p) => p['isActive'] == true).length} actifs", Icons.local_offer_rounded, Colors.purple),
      ]),
      const SizedBox(height: 40),
      const Text("Dernières activités", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      _buildMiniOrdersList(),
    ]);
  }

  // ─── Orders ───────────────────────────────────────────────────────────────
  Widget _buildOrdersView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Gestion des Commandes & Escrow", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 25),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('DATE')),
            DataColumn(label: Text('CLIENT')),
            DataColumn(label: Text('MONTANT')),
            DataColumn(label: Text('HASH (TXID)')),
            DataColumn(label: Text('PROMO')),
            DataColumn(label: Text('STATUT')),
            DataColumn(label: Text('ACTION')),
          ],
          rows: _orders.map((o) {
            final String status    = o['status'] ?? 'PENDING';
            final bool   isPending = status == 'PENDING_ADMIN';
            final String promo     = o['promoCode'] != null ? '${o['promoCode']} (−\$${o['promoDiscount']?.toStringAsFixed(2) ?? '0'})' : '—';
            return DataRow(cells: [
              DataCell(Text(o['createdAt']?.toString().substring(0, 10) ?? '')),
              DataCell(Text(o['buyerName'] ?? 'Anonyme')),
              DataCell(Text("${o['totalAmount']}\$")),
              DataCell(Text(o['transactionHash']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 10, color: Colors.blue))),
              DataCell(Text(promo, style: TextStyle(fontSize: 11, color: promo == '—' ? Colors.grey : Colors.purple, fontWeight: FontWeight.w600))),
              DataCell(Text(status, style: TextStyle(color: isPending ? Colors.orange : Colors.green, fontWeight: FontWeight.bold, fontSize: 11))),
              DataCell(isPending
                  ? ElevatedButton(
                      onPressed: () => _validateOrder(o['_id']),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      child: const Text("VALIDER", style: TextStyle(fontSize: 9)),
                    )
                  : const Icon(Icons.check_circle, color: Colors.green, size: 20)),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  // ─── NOUVEAU : Onglet Codes Promo ─────────────────────────────────────────
  Widget _buildPromoView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Codes Promo", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        ElevatedButton.icon(
          onPressed: _showCreatePromoDialog,
          icon: const Icon(Icons.add),
          label: const Text("NOUVEAU CODE"),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
        ),
      ]),
      const SizedBox(height: 10),
      // Stats rapides
      Row(children: [
        _buildPromoStat("Codes actifs",   "${_promoCodes.where((p) => p['isActive'] == true).length}",  Colors.green),
        const SizedBox(width: 15),
        _buildPromoStat("Codes inactifs", "${_promoCodes.where((p) => p['isActive'] == false).length}", Colors.grey),
        const SizedBox(width: 15),
        _buildPromoStat("Utilisations",   "${_promoCodes.fold(0, (s, p) => s + (p['usageCount'] as int? ?? 0))}", Colors.blue),
      ]),
      const SizedBox(height: 20),
      if (_promoCodes.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(60),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: Column(children: const [
            Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 10),
            Text("Aucun code promo créé.", style: TextStyle(color: Colors.grey)),
          ]),
        )
      else
        Container(
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('CODE')),
              DataColumn(label: Text('RÉDUCTION')),
              DataColumn(label: Text('UTILISATIONS')),
              DataColumn(label: Text('EXPIRATION')),
              DataColumn(label: Text('STATUT')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: _promoCodes.map((p) {
              final bool   isActive   = p['isActive'] == true;
              final String expiration = p['expiresAt'] != null
                  ? p['expiresAt'].toString().substring(0, 10)
                  : 'Illimité';
              final String usage = p['maxUsage'] != null
                  ? '${p['usageCount']} / ${p['maxUsage']}'
                  : '${p['usageCount']} / ∞';

              return DataRow(cells: [
                DataCell(Text(p['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2))),
                DataCell(Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('−${p['discount']}%', style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
                )),
                DataCell(Text(usage, style: const TextStyle(fontSize: 12))),
                DataCell(Text(expiration, style: const TextStyle(fontSize: 12))),
                DataCell(Switch(
                  value: isActive,
                  activeColor: Colors.green,
                  onChanged: (_) => _togglePromo(p['_id'], isActive),
                )),
                DataCell(IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                  onPressed: () => _showDeletePromoConfirm(p['_id'], p['code']),
                )),
              ]);
            }).toList(),
          ),
        ),
    ]);
  }

  Widget _buildPromoStat(String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    ));
  }

  void _showCreatePromoDialog() {
    final codeCtrl      = TextEditingController();
    final discountCtrl  = TextEditingController();
    final expiresCtrl   = TextEditingController();
    final maxUsageCtrl  = TextEditingController();

    showDialog(context: context, builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.local_offer_rounded, color: Color(0xFF1A237E), size: 20),
        SizedBox(width: 8),
        Text("Créer un code promo", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ]),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _adminField(codeCtrl, "Code (ex: PLEXUS20)", Icons.label_outline),
        const SizedBox(height: 12),
        _adminField(discountCtrl, "Réduction en % (ex: 20)", Icons.percent_rounded, isNumber: true),
        const SizedBox(height: 12),
        _adminField(expiresCtrl, "Date expiration (AAAA-MM-JJ) — optionnel", Icons.calendar_today_outlined),
        const SizedBox(height: 12),
        _adminField(maxUsageCtrl, "Nb max utilisations — optionnel", Icons.repeat_rounded, isNumber: true),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULER")),
        ElevatedButton(
          onPressed: () {
            final code     = codeCtrl.text.trim();
            final discount = double.tryParse(discountCtrl.text) ?? 0;
            final maxUsage = int.tryParse(maxUsageCtrl.text);
            if (code.isEmpty || discount <= 0 || discount > 100) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code et réduction (1–100%) requis."), backgroundColor: Colors.orange));
              return;
            }
            Navigator.pop(c);
            _createPromo(code, discount, expiresCtrl.text.trim().isEmpty ? null : expiresCtrl.text.trim(), maxUsage);
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
          child: const Text("CRÉER"),
        ),
      ],
    ));
  }

  void _showDeletePromoConfirm(String id, String code) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text('Supprimer "$code" ?'),
      content: const Text("Cette action est irréversible."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULER")),
        ElevatedButton(
          onPressed: () { Navigator.pop(c); _deletePromo(id); },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text("SUPPRIMER"),
        ),
      ],
    ));
  }

  Widget _adminField(TextEditingController ctrl, String label, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  // ─── Mini orders list (dashboard) ─────────────────────────────────────────
  Widget _buildMiniOrdersList() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(children: _orders.take(5).map((o) => ListTile(
        leading: const Icon(Icons.shopping_cart_outlined),
        title: Text("Commande #${o['_id']?.toString().substring(0, 8)}"),
        subtitle: Text("Client: ${o['buyerName'] ?? 'Anonyme'}"),
        trailing: Text("${o['totalAmount']}\$", style: const TextStyle(fontWeight: FontWeight.bold)),
      )).toList()),
    );
  }

  Widget _buildStatBox(String t, String v, IconData i, Color c) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[100]!)),
      child: Column(children: [
        Icon(i, color: c, size: 30),
        const SizedBox(height: 10),
        Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(t.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ]),
    ));
  }

  // ─── Views inchangées ─────────────────────────────────────────────────────
  Widget _buildProductsView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Gestion du Catalogue", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: DataTable(
          columns: const [DataColumn(label: Text('IMAGE')), DataColumn(label: Text('TITRE')), DataColumn(label: Text('PRIX')), DataColumn(label: Text('ACTION'))],
          rows: _allProducts.map((p) => DataRow(cells: [
            DataCell(Image.network(AdminConfig.getImageUrl(p['thumbnail']), height: 30, errorBuilder: (c, e, s) => const Icon(Icons.image))),
            DataCell(Text(p['title'] ?? '')),
            DataCell(Text("${p['price']}\$")),
            DataCell(IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: () => _deleteItem('products', p['_id']))),
          ])).toList(),
        ),
      ),
    ]);
  }

  Widget _buildSellersView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Vérifications KYC Vendeurs", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 30),
      if (_pendingSellers.isEmpty)
        const Center(child: Text("Tout est à jour ! Aucun vendeur en attente."))
      else
        GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 0.75),
          itemCount: _pendingSellers.length,
          itemBuilder: (context, i) {
            final s = _pendingSellers[i];
            return Card(child: Column(children: [
              const SizedBox(height: 15),
              CircleAvatar(radius: 40, backgroundImage: NetworkImage(AdminConfig.getImageUrl(s['selfie']))),
              const SizedBox(height: 10),
              Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const Spacer(),
              ElevatedButton(onPressed: () => _showDocs(s), child: const Text("VOIR DOCS")),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: () => _approveSeller(s['_id']), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text("APPROUVER")),
              const SizedBox(height: 15),
            ]));
          },
        ),
    ]);
  }

  void _showDocs(dynamic s) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text("Documents de ${s['name']}"),
      content: SingleChildScrollView(child: Column(children: [
        const Text("CNI RECTO"), Image.network(AdminConfig.getImageUrl(s['idFront'])),
        const SizedBox(height: 10),
        const Text("CNI VERSO"), Image.network(AdminConfig.getImageUrl(s['idBack'])),
      ])),
    ));
  }

  Widget _buildUsersView() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: DataTable(
        columns: const [DataColumn(label: Text('NOM')), DataColumn(label: Text('EMAIL')), DataColumn(label: Text('RÔLE')), DataColumn(label: Text('ACTION'))],
        rows: _allUsers.map((u) => DataRow(cells: [
          DataCell(Text(u['name'] ?? '')),
          DataCell(Text(u['email'] ?? '')),
          DataCell(Text(u['role']?.toUpperCase() ?? '')),
          DataCell(IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: () => _deleteItem('users', u['_id']))),
        ])).toList(),
      ),
    );
  }

  Widget _buildDisputesView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Gestion des Litiges (Escrow)", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      if (_disputes.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.all(50), child: Text("Aucun litige ouvert")))
      else
        ..._disputes.map((d) => Container(
          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.red.withOpacity(0.2))),
          child: Column(children: [
            Text("Commande #${d['orderId']?.toString().substring(0, 8)}"),
            Text("Motif: ${d['reason'] ?? d['motif'] ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(children: [
              ElevatedButton(onPressed: () => _resolveDispute(d['_id'], 'REFUND'),     style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),child: const Text("REMBOURSER CLIENT")),
              const SizedBox(width: 15),
              ElevatedButton(onPressed: () => _resolveDispute(d['_id'], 'PAY_SELLER'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text("PAYER VENDEUR")),
            ]),
          ]),
        )),
    ]);
  }

  Widget _buildCategoriesView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Gestion des Catégories",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ElevatedButton.icon(
          onPressed: _showAddCategoryDialog,
          icon: const Icon(Icons.add),
          label: const Text("NOUVELLE CATÉGORIE"),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white),
        ),
      ]),
      const SizedBox(height: 20),
      GridView.builder(
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 15,
            mainAxisSpacing: 15,
            childAspectRatio: 0.85),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final List<dynamic> subs = cat['subCategories'] ?? [];
          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  AdminConfig.getImageUrl(cat['imageUrl']),
                  height: 60, width: 60, fit: BoxFit.cover,
                  errorBuilder: (c, e, s) =>
                      const Icon(Icons.category, size: 40, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              Text(cat['name'] ?? '',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              if (subs.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${subs.length} sous-catégorie(s)',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 16, color: Color(0xFF1A237E)),
                  onPressed: () => _showEditCategoryDialog(cat),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                  onPressed: () => _deleteItem('categories', cat['_id']),
                ),
              ]),
            ]),
          );
        },
      ),
    ]);
  }

void _showAddCategoryDialog() {
  final nameCtrl = TextEditingController();
  String? selectedImagePath;
  String? selectedImageBytes;

  showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.category_rounded, color: Color(0xFF1A237E), size: 20),
          SizedBox(width: 8),
          Text("Nouvelle catégorie",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: "Nom de la catégorie",
                prefixIcon: const Icon(Icons.label_outline, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),

            // Zone upload image
            GestureDetector(
              onTap: () async {
                // Sur web on utilise les bytes
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 500,
                  maxHeight: 500,
                );
                if (picked != null) {
                  final bytes = await picked.readAsBytes();
                  setStateDialog(() {
                    selectedImagePath  = picked.path;
                    selectedImageBytes = base64Encode(bytes);
                  });
                }
              },
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectedImagePath != null
                        ? const Color(0xFF1A237E)
                        : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: selectedImageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          base64Decode(selectedImageBytes!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined,
                              size: 36, color: Colors.grey),
                          SizedBox(height: 8),
                          Text("Cliquer pour choisir une image",
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("ANNULER"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Le nom est requis"),
                  backgroundColor: Colors.orange,
                ));
                return;
              }

              // Upload via multipart
              final uri = Uri.parse(
                  '${AdminConfig.baseUrl}/categories');
              final request = http.MultipartRequest('POST', uri);
              request.headers.addAll(_headers
                ..remove('Content-Type'));
              request.fields['name'] = nameCtrl.text.trim();

              if (selectedImagePath != null &&
                  selectedImageBytes != null) {
                final bytes = base64Decode(selectedImageBytes!);
                request.files.add(http.MultipartFile.fromBytes(
                  'image',
                  bytes,
                  filename: 'category.png',
                ));
              }

              final response = await request.send();
              if (response.statusCode == 201) {
                _fetchData();
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Catégorie créée avec succès !"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
            ),
            child: const Text("CRÉER"),
          ),
        ],
      ),
    ),
  );
}



void _showEditCategoryDialog(Map<String, dynamic> cat) {
  final nameCtrl = TextEditingController(text: cat['name'] ?? '');
  final subCtrl  = TextEditingController();
  String? selectedImageBytes;
  List<String> subs = List<String>.from(cat['subCategories'] ?? []);

  showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.edit, color: Color(0xFF1A237E), size: 20),
          SizedBox(width: 8),
          Text("Modifier la catégorie",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // ── Nom ──────────────────────────────────────────────────
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: "Nom de la catégorie",
                  prefixIcon: const Icon(Icons.label_outline, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              // ── Image ────────────────────────────────────────────────
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 500, maxHeight: 500,
                  );
                  if (picked != null) {
                    final bytes = await picked.readAsBytes();
                    setStateDialog(() => selectedImageBytes = base64Encode(bytes));
                  }
                },
                child: Container(
                  width: double.infinity, height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: selectedImageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            base64Decode(selectedImageBytes!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : cat['imageUrl'] != null && cat['imageUrl'] != ''
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                AdminConfig.getImageUrl(cat['imageUrl']),
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_upload_outlined,
                                    size: 30, color: Colors.grey),
                                SizedBox(height: 6),
                                Text("Changer l'image",
                                    style: TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Sous-catégories existantes ────────────────────────────
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("SOUS-CATÉGORIES",
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              const SizedBox(height: 8),
              if (subs.isEmpty)
                const Text("Aucune sous-catégorie",
                    style: TextStyle(color: Colors.grey, fontSize: 12))
              else
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: subs.map((s) => Chip(
                    label: Text(s, style: const TextStyle(fontSize: 11)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setStateDialog(() => subs.remove(s)),
                    backgroundColor: const Color(0xFFF0F3FF),
                  )).toList(),
                ),
              const SizedBox(height: 12),

              // ── Ajouter sous-catégorie ───────────────────────────────
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: subCtrl,
                    decoration: InputDecoration(
                      hintText: "Nouvelle sous-catégorie",
                      hintStyle: const TextStyle(fontSize: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (subCtrl.text.trim().isNotEmpty) {
                      setStateDialog(() {
                        subs.add(subCtrl.text.trim());
                        subCtrl.clear();
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  child: const Text("Ajouter"),
                ),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("ANNULER"),
          ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.parse(
                  '${AdminConfig.baseUrl}/categories/${cat['_id']}');
              final request = http.MultipartRequest('PUT', uri);
              request.headers.addAll({
                'Authorization': 'Bearer $_adminToken',
              });
              request.fields['name']          = nameCtrl.text.trim();
              request.fields['subCategories'] = json.encode(subs);

              if (selectedImageBytes != null) {
                final bytes = base64Decode(selectedImageBytes!);
                request.files.add(http.MultipartFile.fromBytes(
                  'image', bytes, filename: 'category.png',
                ));
              }

              final response = await request.send();
              if (response.statusCode == 200) {
                _fetchData();
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Catégorie mise à jour !"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
            ),
            child: const Text("SAUVEGARDER"),
          ),
        ],
      ),
    ),
  );
}




  // ─── Sidebar ──────────────────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 250, color: Colors.white,
      child: Column(children: [
        const Padding(padding: EdgeInsets.all(30), child: Text("PLEXUS ADMIN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A237E)))),
        _sidebarItem(Icons.dashboard_rounded,     "Dashboard",    0),
        _sidebarItem(Icons.shopping_cart_rounded, "Commandes",    6),
        _sidebarItem(Icons.local_offer_rounded,   "Codes Promo",  7),  // NOUVEAU
        _sidebarItem(Icons.verified_user_rounded, "Vendeurs KYC", 1),
        _sidebarItem(Icons.inventory_2_rounded,   "Catalogue",    2),
        _sidebarItem(Icons.category_rounded,      "Catégories",   3),
        _sidebarItem(Icons.people_alt_rounded,    "Utilisateurs", 4),
        _sidebarItem(Icons.gavel_rounded,         "Litiges",      5),
        const Spacer(),
        _sidebarItem(Icons.logout_rounded,        "Déconnexion",  99),
      ]),
    );
  }

  Widget _sidebarItem(IconData i, String t, int idx) {
    bool sel = _selectedIndex == idx;
    return ListTile(
      leading: Icon(i, color: sel ? const Color(0xFF1A237E) : Colors.grey),
      title: Text(t, style: TextStyle(color: sel ? const Color(0xFF1A237E) : Colors.black87, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
      onTap: () => idx == 99 ? _logout() : setState(() => _selectedIndex = idx),
    );
  }

  Widget _buildTopbar() {
    return Container(
      height: 70, color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(children: [
        Text("Système Administrateur PLEXUS"),
        Spacer(),
        Icon(Icons.notifications_none),
        SizedBox(width: 20),
        CircleAvatar(backgroundColor: Color(0xFF1A237E), child: Icon(Icons.person, color: Colors.white, size: 20)),
      ]),
    );
  }
}