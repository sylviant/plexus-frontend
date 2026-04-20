import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart'; // Import ajouté

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<dynamic> _wallets = [];
  bool _isLoading = true;
  double _balance = 0.0; 

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      // Utilisation de ApiConfig
      final wResponse = await http.get(Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/wallets'));
      final bResponse = await http.get(Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/balance'));
      
      if (wResponse.statusCode == 200 && bResponse.statusCode == 200) {
        setState(() {
          _wallets = json.decode(wResponse.body);
          _balance = (json.decode(bResponse.body)['balance'] as num).toDouble();
        });
      }
    } catch (e) {
      debugPrint('Erreur synchronisation: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showWithdrawDialog() {
    if (_wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajoutez d'abord un portefeuille de retrait")));
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Retirer vos gains", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Solde : \$${_balance.toStringAsFixed(2)}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            const Text("Sélectionnez le portefeuille de destination :"),
            const SizedBox(height: 10),
            ..._wallets.map((w) => ListTile(
              leading: const Icon(Icons.account_balance_wallet, color: Color(0xFF283593)),
              title: Text(w['name'] ?? 'Wallet'),
              subtitle: Text(w['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                _requestWithdrawal(w['address']);
              },
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _requestWithdrawal(String walletAddress) async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null || _balance <= 0) return;

    setState(() => _isLoading = true);
    try {
      // Utilisation de ApiConfig
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/withdrawals'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': user.id,
          'walletAddress': walletAddress,
          'amount': _balance,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Demande de retrait transmise !"), backgroundColor: Colors.green),
        );
        _fetchUserData();
      }
    } catch (e) {
      debugPrint("Erreur retrait: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddWalletDialog() {
    final nameCtrl = TextEditingController();
    final networkCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Ajouter un Portefeuille"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nom (ex: Mon Wallet USDT)")),
            TextField(controller: networkCtrl, decoration: const InputDecoration(labelText: "Réseau (ex: TRC20)")),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: "Adresse Blockchain")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              _addWallet(nameCtrl.text, networkCtrl.text, addressCtrl.text);
              Navigator.pop(context);
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  Future<void> _addWallet(String name, String network, String address) async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null || name.isEmpty || address.isEmpty) return;

    try {
      // Utilisation de ApiConfig
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/wallets'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'name': name, 'network': network, 'address': address}),
      );

      if (response.statusCode == 201) {
        _fetchUserData(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Portefeuille enregistré !"), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Erreur ajout: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF283593);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Paiements & Gains', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _fetchUserData,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryBlue, Color(0xFF3F51B5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Solde disponible", style: TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("\$${_balance.toStringAsFixed(2)}", 
                              style: const TextStyle(color: Colors.white, fontSize: 35, fontWeight: FontWeight.bold)),
                            ElevatedButton(
                              onPressed: _showWithdrawDialog, 
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: primaryBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text("Retirer"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text("Mes adresses de retrait", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  if (_wallets.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: Text("Aucun portefeuille lié.", style: TextStyle(color: Colors.grey)),
                    ))
                  else
                    ..._wallets.map((wallet) => _buildWalletCard(context, wallet, primaryBlue)),
                  const SizedBox(height: 30),
                  OutlinedButton.icon(
                    onPressed: _showAddWalletDialog,
                    icon: const Icon(Icons.add),
                    label: const Text("Ajouter une adresse"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      side: const BorderSide(color: primaryBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildWalletCard(BuildContext context, Map<String, dynamic> wallet, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(wallet['name'] ?? 'Inconnu', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(wallet['network'] ?? 'Réseau', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  wallet['address'] ?? '',
                  style: const TextStyle(color: Colors.black54, fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: wallet['address'] ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Adresse copiée !")));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
