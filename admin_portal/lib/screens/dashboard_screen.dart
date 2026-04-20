import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0; 
  bool _isLoading = true;
  String _debugMessage = "Tentative de connexion...";
  String? _adminToken;
  
  List<dynamic> _orders = [];
  List<dynamic> _disputes = [];
  List<dynamic> _pendingSellers = [];
  List<dynamic> _allUsers = [];
  
  static const String serverUrl = 'http://192.168.1.201:5000';

  @override
  void initState() {
    super.initState();
    _loadTokenAndFetch();
  }

  Future<void> _loadTokenAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _adminToken = prefs.getString('admin_token');
    
    if (_adminToken == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    _fetchData();
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_adminToken',
  };

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _debugMessage = "Récupération des données sécurisées...";
    });

    try {
      final ordersRes = await http.get(Uri.parse('$serverUrl/api/orders'), headers: _headers);
      
      if (ordersRes.statusCode == 200) {
        final disputesRes = await http.get(Uri.parse('$serverUrl/api/disputes'), headers: _headers);
        final usersRes = await http.get(Uri.parse('$serverUrl/api/users'), headers: _headers);

        if (mounted) {
          setState(() {
            _orders = json.decode(ordersRes.body);
            if (disputesRes.statusCode == 200) _disputes = json.decode(disputesRes.body);
            if (usersRes.statusCode == 200) {
              _allUsers = json.decode(usersRes.body);
              _pendingSellers = _allUsers.where((u) => u['role'] == 'seller' && u['isApproved'] != true).toList();
            }
            _debugMessage = "Connecté ! Base de données chargée.";
            _isLoading = false;
          });
        }
      } else if (ordersRes.statusCode == 401) {
        setState(() {
          _debugMessage = "Session expirée. Veuillez vous reconnecter.";
          _isLoading = false;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pushReplacementNamed(context, '/login');
        });
      } else {
        setState(() {
          _debugMessage = "Erreur ${ordersRes.statusCode}: Accès refusé par le serveur.";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _debugMessage = "ERREUR RÉSEAU : $e";
          _isLoading = false;
        });
      }
    }
  }

  // --- ACTIONS LOGIQUES PLEXUS ---
  Future<void> _verifyPayment(String orderId) async {
    try {
      final res = await http.put(Uri.parse('$serverUrl/api/orders/$orderId/approve'), headers: _headers);
      if (res.statusCode == 200) _fetchData();
    } catch(e) { debugPrint(e.toString()); }
  }

  Future<void> _approveSeller(String userId) async {
    try {
      final res = await http.put(Uri.parse('$serverUrl/api/admin/approve-seller/$userId'), headers: _headers);
      if (res.statusCode == 200) _fetchData();
    } catch(e) { debugPrint(e.toString()); }
  }

  Future<void> _resolveDispute(String disputeId, String action) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/admin/disputes/$disputeId/resolve'),
        headers: _headers,
        body: json.encode({'action': action}),
      );
      if (res.statusCode == 200) _fetchData();
    } catch(e) { debugPrint(e.toString()); }
  }

  // ... (Analytics et build UI restent identiques)
  Map<String, dynamic> _getAnalytics() {
    double totalVolume = _orders.fold(0, (sum, item) => sum + (double.tryParse(item['totalAmount']?.toString() ?? '0') ?? 0));
    double platformFees = totalVolume * 0.03;
    int news = _allUsers.where((u) {
      if (u['createdAt'] == null) return false;
      try { DateTime created = DateTime.parse(u['createdAt']); return DateTime.now().difference(created).inHours < 24; } catch(_) { return false; }
    }).length;
    int completed = _orders.where((o) => o['status'] == 'DELIVERED').length;
    double success = _orders.isEmpty ? 0 : (completed / _orders.length) * 100;
    return {'vol': totalVolume, 'fees': platformFees, 'news': news, 'success': success};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopbar(),
                Container(
                  width: double.infinity,
                  color: Colors.blue[50],
                  padding: const EdgeInsets.all(8),
                  child: Text("SÉCURITÉ : ${_adminToken != null ? 'Token Actif' : 'Pas de Token'} | $_debugMessage", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                ),
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: accentColor))
                    : SingleChildScrollView(padding: const EdgeInsets.all(30), child: _buildMainContent()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    final stats = _getAnalytics();
    switch (_selectedIndex) {
      case 0: return _buildEcommerceDashboard(stats);
      case 1: return _buildDisputesView();
      case 2: return _buildSellersView();
      case 3: return _buildUsersView();
      default: return _buildEcommerceDashboard(stats);
    }
  }

  Widget _buildEcommerceDashboard(Map<String, dynamic> stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("Plexus Secure Analytics", "/ Dashboard / Realtime"),
        const SizedBox(height: 30),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          childAspectRatio: 1.5,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          children: [
            _buildStatCard("Volume Escrow", "${stats['vol'].toStringAsFixed(2)}\$", Icons.account_balance_wallet, Colors.blue),
            _buildStatCard("Revenus (3%)", "${stats['fees'].toStringAsFixed(2)}\$", Icons.monetization_on, Colors.green),
            _buildStatCard("Nouveaux Users", "+${stats['news']}", Icons.person_add, Colors.purple),
            _buildStatCard("Taux Réussite", "${stats['success'].toStringAsFixed(1)}%", Icons.trending_up, Colors.orange),
          ],
        ),
        const SizedBox(height: 40),
        _buildSectionTitle("Dernières Transactions Blockchain"),
        const SizedBox(height: 15),
        _buildOrdersTable(),
      ],
    );
  }

  static const Color accentColor = Color(0xFF7366FF);
  static const Color bgColor = Color(0xFFF8F9FD);

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ]),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260, color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.all(25.0), child: Text("PLEXUS ADMIN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor))),
        const SizedBox(height: 20),
        _sidebarSectionTitle("ANALYTIQUE"),
        _sidebarItem(Icons.analytics_outlined, "Tableau de Bord", 0),
        _sidebarItem(Icons.people_outline, "Utilisateurs", 3),
        _sidebarSectionTitle("GESTION"),
        _sidebarItem(Icons.gavel_outlined, "Litiges", 1, hasBadge: true, badgeText: _disputes.length.toString()),
        _sidebarItem(Icons.verified_user_outlined, "Vérification KYC", 2, hasBadge: true, badgeText: _pendingSellers.length.toString(), badgeColor: Colors.orange),
        const Spacer(),
        _sidebarItem(Icons.logout, "Déconnexion", 99),
      ]),
    );
  }

  Widget _sidebarItem(IconData icon, String title, int index, {bool hasBadge = false, String? badgeText, Color? badgeColor}) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () {
        if (index == 99) {
          SharedPreferences.getInstance().then((p) => p.remove('admin_token'));
          Navigator.pushReplacementNamed(context, '/login');
        } else setState(() => _selectedIndex = index);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
        decoration: BoxDecoration(color: isSelected ? accentColor.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: isSelected ? accentColor : Colors.grey[600], size: 20),
          const SizedBox(width: 15),
          Expanded(child: Text(title, style: TextStyle(color: isSelected ? accentColor : Colors.grey[700], fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
          if (hasBadge && badgeText != "0")
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: badgeColor ?? Colors.redAccent, shape: BoxShape.circle), child: Text(badgeText!, style: const TextStyle(color: Colors.white, fontSize: 8))),
        ]),
      ),
    );
  }

  Widget _buildTopbar() {
    return Container(
      height: 80, padding: const EdgeInsets.symmetric(horizontal: 30), color: Colors.white,
      child: Row(children: [
        const Text("Plexus Global Solutions FZ-LLC", style: TextStyle(color: Colors.grey, fontSize: 12)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.refresh, color: accentColor), onPressed: _fetchData),
        const SizedBox(width: 20),
        const VerticalDivider(width: 1, indent: 25, endIndent: 25),
        const SizedBox(width: 20),
        const Text("Directeur Admin", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 15),
        const CircleAvatar(backgroundColor: accentColor, child: Icon(Icons.person, color: Colors.white)),
      ]),
    );
  }

  Widget _buildOrdersTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('ACHETEUR')),
          DataColumn(label: Text('MONTANT')),
          DataColumn(label: Text('STATUT')),
          DataColumn(label: Text('ACTION')),
        ],
        rows: _orders.map((o) => DataRow(cells: [
          DataCell(Text(o['_id']?.toString().substring(0, 8) ?? 'N/A')),
          DataCell(Text(o['buyerName'] ?? 'User')),
          DataCell(Text("${o['totalAmount']}\$")),
          DataCell(_buildStatusBadge(o['status'] ?? 'PENDING')),
          DataCell(
            o['status'] == 'PENDING_SHIPPING'
            ? ElevatedButton(onPressed: () => _verifyPayment(o['_id']), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text("VALIDER", style: TextStyle(fontSize: 10, color: Colors.white)))
            : const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
        ])).toList(),
      ),
    );
  }

  Widget _buildUsersView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("Utilisateurs PLEXUS", "/ Dashboard / Users"),
        const SizedBox(height: 30),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('NOM')),
              DataColumn(label: Text('EMAIL')),
              DataColumn(label: Text('RÔLE')),
              DataColumn(label: Text('SOLDE')),
            ],
            rows: _allUsers.map((u) => DataRow(cells: [
              DataCell(Text(u['name'] ?? '')),
              DataCell(Text(u['email'] ?? '')),
              DataCell(Text(u['role']?.toUpperCase() ?? '')),
              DataCell(Text("${u['balance'] ?? 0}\$")),
            ])).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDisputesView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("Gestion des Litiges", "/ Dashboard / Disputes"),
        const SizedBox(height: 30),
        if (_disputes.isEmpty) const Center(child: Text("Aucun litige"))
        else ..._disputes.map((d) => _buildDisputeCard(d)),
      ],
    );
  }

  Widget _buildDisputeCard(dynamic d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Litige Commande #${d['orderId']?.toString().substring(0,8) ?? 'ID'}", style: const TextStyle(fontWeight: FontWeight.bold)),
          _buildStatusBadge(d['status'] ?? 'OPEN'),
        ]),
        const Divider(height: 30),
        Text("Motif: ${d['motif'] ?? 'Non spécifié'}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        Text(d['description'] ?? ''),
        const SizedBox(height: 15),
        Row(children: [
          ElevatedButton(onPressed: () => _resolveDispute(d['_id'], 'REFUND'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text("REMBOURSER")),
          const SizedBox(width: 10),
          ElevatedButton(onPressed: () => _resolveDispute(d['_id'], 'PAY_SELLER'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text("PAYER VENDEUR")),
        ])
      ]),
    );
  }

  Widget _buildSellersView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("KYC Verification", "/ Dashboard / KYC"),
        const SizedBox(height: 30),
        if (_pendingSellers.isEmpty) const Center(child: Text("Aucun vendeur à approuver"))
        else GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 0.8),
          itemCount: _pendingSellers.length,
          itemBuilder: (context, i) => _buildSellerKYCCard(_pendingSellers[i]),
        ),
      ],
    );
  }

  Widget _buildSellerKYCCard(dynamic s) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
      child: Column(children: [
        CircleAvatar(radius: 40, backgroundImage: NetworkImage("$serverUrl/${s['selfie']}")),
        const SizedBox(height: 10),
        Text(s['name'] ?? 'Nom inconnu', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(s['email'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const Spacer(),
        Row(children: [
          Expanded(child: TextButton(onPressed: () => _showDocsPopup(s), child: const Text("DOCS"))),
          ElevatedButton(onPressed: () => _approveSeller(s['_id']), style: ElevatedButton.styleFrom(backgroundColor: accentColor), child: const Text("APPROUVER", style: TextStyle(fontSize: 10, color: Colors.white))),
        ])
      ]),
    );
  }

  void _showDocsPopup(dynamic s) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text("Documents de ${s['name']}"),
      content: SingleChildScrollView(child: Column(children: [
        const Text("CNI RECTO"), Image.network("$serverUrl/${s['idFront']}"),
        const SizedBox(height: 10),
        const Text("CNI VERSO"), Image.network("$serverUrl/${s['idBack']}"),
      ])),
    ));
  }

  void _openBscScan(String? hash) async {
    if (hash == null || hash.isEmpty) return;
    final Uri url = Uri.parse('https://bscscan.com/tx/$hash');
    if (!await launchUrl(url)) debugPrint('Could not launch $url');
  }

  Widget _buildHeader(String title, String path) { return Row(children: [Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const Spacer(), Text(path, style: const TextStyle(color: Colors.grey, fontSize: 11))]); }
  Widget _buildSectionTitle(String title) { return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)); }
  Widget _sidebarSectionTitle(String title) { return Padding(padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10), child: Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1))); }
  Widget _buildStatusBadge(String status) {
    Color color = (status == 'PAID' || status == 'DELIVERED') ? Colors.green : (status == 'DISPUTED' ? Colors.red : Colors.orange);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)));
  }
}
