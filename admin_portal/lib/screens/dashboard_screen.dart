import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../admin_config.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0; 
  bool _isLoading = true;
  String _debugMessage = "Initialisation...";
  String? _adminToken;
  
  List<dynamic> _orders = [];
  List<dynamic> _disputes = [];
  List<dynamic> _pendingSellers = [];
  List<dynamic> _allUsers = [];
  List<dynamic> _categories = [];
  List<dynamic> _allProducts = [];

  @override
  void initState() {
    super.initState();
    _loadTokenAndFetch();
  }

  Future<void> _loadTokenAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _adminToken = prefs.getString('admin_token');
    
    if (_adminToken == null || _adminToken!.isEmpty) {
      _logout();
      return;
    }
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
    setState(() {
      _isLoading = true;
      _debugMessage = "Synchronisation Northflank...";
    });

    try {
      final usersRes = await http.get(Uri.parse('${AdminConfig.baseUrl}/users'), headers: _headers);
      
      if (usersRes.statusCode == 200) {
        final ordersRes = await http.get(Uri.parse('${AdminConfig.baseUrl}/orders'), headers: _headers);
        final disputesRes = await http.get(Uri.parse('${AdminConfig.baseUrl}/disputes'), headers: _headers);
        final catsRes = await http.get(Uri.parse('${AdminConfig.baseUrl}/categories'), headers: _headers);
        final prodsRes = await http.get(Uri.parse('${AdminConfig.baseUrl}/products'), headers: _headers);

        if (mounted) {
          setState(() {
            _allUsers = json.decode(usersRes.body);
            _orders = json.decode(ordersRes.body);
            if (disputesRes.statusCode == 200) _disputes = json.decode(disputesRes.body);
            if (catsRes.statusCode == 200) _categories = json.decode(catsRes.body);
            if (prodsRes.statusCode == 200) {
              final data = json.decode(prodsRes.body);
              _allProducts = data['products'] ?? [];
            }
            _pendingSellers = _allUsers.where((u) => u['role'] == 'seller' && u['isApproved'] != true).toList();
            _debugMessage = "Administrateur Connecté";
            _isLoading = false;
          });
        }
      } else {
        setState(() { _debugMessage = "Erreur session"; _isLoading = false; });
        if (usersRes.statusCode == 401) _logout();
      }
    } catch (e) {
      if (mounted) setState(() { _debugMessage = "Erreur: $e"; _isLoading = false; });
    }
  }

  // Action pour valider une commande
  Future<void> _validateOrder(String orderId) async {
    try {
      final res = await http.put(
        Uri.parse('${AdminConfig.baseUrl}/admin/orders/$orderId/validate'), 
        headers: _headers
      );
      if (res.statusCode == 200) {
        _fetchData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Paiement validé ! Vendeur notifié."), backgroundColor: Colors.green),
        );
      }
    } catch(e) { debugPrint(e.toString()); }
  }

  Future<void> _approveSeller(String userId) async {
    try {
      final res = await http.put(Uri.parse('${AdminConfig.baseUrl}/admin/approve-seller/$userId'), headers: _headers);
      if (res.statusCode == 200) _fetchData();
    } catch(e) { debugPrint(e.toString()); }
  }

  Future<void> _resolveDispute(String id, String action) async {
    try {
      final res = await http.post(
        Uri.parse('${AdminConfig.baseUrl}/admin/disputes/$id/resolve'),
        headers: _headers,
        body: json.encode({'action': action}),
      );
      if (res.statusCode == 200) _fetchData();
    } catch(e) { debugPrint(e.toString()); }
  }

  Future<void> _deleteItem(String type, String id) async {
    try {
      final res = await http.delete(Uri.parse('${AdminConfig.baseUrl}/$type/$id'), headers: _headers);
      if (res.statusCode == 200) _fetchData();
    } catch(e) { debugPrint(e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopbar(),
                _buildStatusBar(),
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
                    : SingleChildScrollView(padding: const EdgeInsets.all(30), child: _buildMainContent()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity, color: const Color(0xFF1A237E),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      child: Text("PLEXUS SECURITY : $_debugMessage", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0: return _buildDashboardView();
      case 1: return _buildSellersView();
      case 2: return _buildProductsView();
      case 3: return _buildCategoriesView();
      case 4: return _buildUsersView();
      case 5: return _buildDisputesView();
      case 6: return _buildOrdersView(); // NOUVEL ONGLET DÉDIÉ
      default: return _buildDashboardView();
    }
  }

  Widget _buildDashboardView() {
    double total = _orders.fold(0, (sum, o) => sum + (double.tryParse(o['totalAmount']?.toString() ?? '0') ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Tableau de Bord Central", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        const SizedBox(height: 25),
        Row(
          children: [
            _buildStatBox("Volume Escrow", "\$${total.toStringAsFixed(2)}", Icons.account_balance_wallet, Colors.blue),
            const SizedBox(width: 20),
            _buildStatBox("Ventes à valider", "${_orders.where((o) => o['status'] == 'PENDING_ADMIN').length}", Icons.notification_important, Colors.orange),
            const SizedBox(width: 20),
            _buildStatBox("Produits Live", "${_allProducts.length}", Icons.inventory_2_rounded, Colors.teal),
            const SizedBox(width: 20),
            _buildStatBox("Litiges", "${_disputes.length}", Icons.gavel_rounded, Colors.red),
          ],
        ),
        const SizedBox(height: 40),
        const Text("Dernières activités", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _buildMiniOrdersList(),
      ],
    );
  }

  Widget _buildOrdersView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Gestion des Commandes & Escrow", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 25),
      Container(
        width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('DATE')),
            DataColumn(label: Text('CLIENT')),
            DataColumn(label: Text('MONTANT')),
            DataColumn(label: Text('HASH (TXID)')),
            DataColumn(label: Text('STATUT')),
            DataColumn(label: Text('ACTION')),
          ],
          rows: _orders.map((o) {
            final String status = o['status'] ?? 'PENDING';
            final bool isPending = status == 'PENDING_ADMIN' || status == 'En attente de vérification';
            return DataRow(cells: [
              DataCell(Text(o['createdAt']?.toString().substring(0, 10) ?? '')),
              DataCell(Text(o['buyerName'] ?? 'Anonyme')),
              DataCell(Text("${o['totalAmount']}\$")),
              DataCell(Text(o['transactionHash']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 10, color: Colors.blue))),
              DataCell(Text(status, style: TextStyle(color: isPending ? Colors.orange : Colors.green, fontWeight: FontWeight.bold, fontSize: 11))),
              DataCell(
                isPending
                ? ElevatedButton(
                    onPressed: () => _validateOrder(o['_id']),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text("VALIDER PAIEMENT", style: TextStyle(fontSize: 9)),
                  )
                : const Icon(Icons.check_circle, color: Colors.green, size: 20)
              ),
            ]);
          }).toList(),
        ),
      )
    ]);
  }

  Widget _buildMiniOrdersList() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(children: _orders.take(5).map((o) => ListTile(
        leading: const Icon(Icons.shopping_cart_outlined),
        title: Text("Commande #${o['_id']?.toString().substring(0,8)}"),
        subtitle: Text("Client: ${o['buyerName'] ?? 'Anonyme'}"),
        trailing: Text("${o['totalAmount']}\$", style: const TextStyle(fontWeight: FontWeight.bold)),
      )).toList()),
    );
  }

  Widget _buildStatBox(String t, String v, IconData i, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[100]!)),
        child: Column(children: [
          Icon(i, color: c, size: 30),
          const SizedBox(height: 10),
          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(t.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ]),
      ),
    );
  }

  Widget _buildProductsView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Gestion du Catalogue", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      Container(
        width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: DataTable(
          columns: const [DataColumn(label: Text('IMAGE')), DataColumn(label: Text('TITRE')), DataColumn(label: Text('PRIX')), DataColumn(label: Text('ACTION'))],
          rows: _allProducts.map((p) => DataRow(cells: [
            DataCell(Image.network(AdminConfig.getImageUrl(p['thumbnail']), height: 30, errorBuilder: (c,e,s) => const Icon(Icons.image))),
            DataCell(Text(p['title'] ?? '')),
            DataCell(Text("${p['price']}\$")),
            DataCell(IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: () => _deleteItem('products', p['_id']))),
          ])).toList(),
        ),
      )
    ]);
  }

  Widget _buildSellersView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Vérifications KYC Vendeurs", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 30),
      if (_pendingSellers.isEmpty) const Center(child: Text("Tout est à jour ! Aucun vendeur en attente."))
      else GridView.builder(
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 0.75),
        itemCount: _pendingSellers.length,
        itemBuilder: (context, i) {
          final s = _pendingSellers[i];
          return Card(
            child: Column(children: [
              const SizedBox(height: 15),
              CircleAvatar(radius: 40, backgroundImage: NetworkImage(AdminConfig.getImageUrl(s['selfie']))),
              const SizedBox(height: 10),
              Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const Spacer(),
              ElevatedButton(onPressed: () => _showDocs(s), child: const Text("VOIR DOCS")),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: () => _approveSeller(s['_id']), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text("APPROUVER")),
              const SizedBox(height: 15),
            ]),
          );
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
      width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
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
      if (_disputes.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(50), child: Text("Aucun litige ouvert")))
      else ..._disputes.map((d) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.red.withOpacity(0.2))),
        child: Column(children: [
          Text("Commande #${d['orderId']?.toString().substring(0,8)}"),
          Text("Motif: ${d['motif']}", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(children: [
            ElevatedButton(onPressed: () => _resolveDispute(d['_id'], 'refund'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text("REMBOURSER CLIENT")),
            const SizedBox(width: 15),
            ElevatedButton(onPressed: () => _resolveDispute(d['_id'], 'pay_seller'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text("PAYER VENDEUR")),
          ])
        ]),
      )),
    ]);
  }

  Widget _buildCategoriesView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Gestion des Catégories", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ElevatedButton.icon(onPressed: () => _showAddCategoryDialog(), icon: const Icon(Icons.add), label: const Text("NOUVELLE CATÉGORIE")),
      ]),
      const SizedBox(height: 20),
      GridView.builder(
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 15, mainAxisSpacing: 15),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          return Card(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.network(AdminConfig.getImageUrl(cat['imageUrl']), height: 40, errorBuilder: (c,e,s) => const Icon(Icons.category)),
                const SizedBox(height: 5),
                Text(cat['name'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () => _deleteItem('categories', cat['_id']))
              ],
            ),
          );
        },
      )
    ]);
  }

  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Ajouter une catégorie"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nom")),
        TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: "Chemin Image")),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULER")),
        ElevatedButton(onPressed: () async {
          final res = await http.post(Uri.parse('${AdminConfig.baseUrl}/categories'), headers: _headers, body: json.encode({'name': nameCtrl.text, 'imageUrl': urlCtrl.text}));
          if (res.statusCode == 201) { _fetchData(); Navigator.pop(c); }
        }, child: const Text("CRÉER")),
      ],
    ));
  }

  Widget _buildSidebar() {
    return Container(
      width: 250, color: Colors.white,
      child: Column(children: [
        const Padding(padding: EdgeInsets.all(30), child: Text("PLEXUS ADMIN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A237E)))),
        _sidebarItem(Icons.dashboard_rounded, "Dashboard", 0),
        _sidebarItem(Icons.shopping_cart_rounded, "Commandes", 6), // NOUVEAU : Index 6
        _sidebarItem(Icons.verified_user_rounded, "Vendeurs KYC", 1),
        _sidebarItem(Icons.inventory_2_rounded, "Catalogue", 2),
        _sidebarItem(Icons.category_rounded, "Catégories", 3),
        _sidebarItem(Icons.people_alt_rounded, "Utilisateurs", 4),
        _sidebarItem(Icons.gavel_rounded, "Litiges", 5),
        const Spacer(),
        _sidebarItem(Icons.logout_rounded, "Déconnexion", 99),
      ]),
    );
  }

  Widget _sidebarItem(IconData i, String t, int idx) {
    bool sel = _selectedIndex == idx;
    return ListTile(
      leading: Icon(i, color: sel ? const Color(0xFF1A237E) : Colors.grey),
      title: Text(t, style: TextStyle(color: sel ? const Color(0xFF1A237E) : Colors.black87, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
      onTap: () {
        if (idx == 99) { _logout(); }
        else { setState(() => _selectedIndex = idx); }
      },
    );
  }

  Widget _buildTopbar() {
    return Container(height: 70, color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [const Text("Système Administrateur PLEXUS"), const Spacer(), const Icon(Icons.notifications_none), const SizedBox(width: 20), const CircleAvatar(backgroundColor: Color(0xFF1A237E), child: Icon(Icons.person, color: Colors.white, size: 20))]));
  }
}
