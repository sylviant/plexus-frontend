import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:intl/intl.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<dynamic> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/orders/user/${user.id}'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _orders = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = "Erreur serveur (${response.statusCode})";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de joindre le serveur.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text('Mes Achats', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.black), onPressed: _fetchOrders)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _orders.isEmpty
                  ? _buildEmptyView()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders.length,
                      itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
                    ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    final String status = order['status'] ?? 'PENDING';
    final DateTime date = DateTime.parse(order['createdAt'] ?? DateTime.now().toIso8601String());
    final double total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    
    // Détermination de l'état simplifié
    final bool isDelivered = status == 'DELIVERED' || status == 'Terminé';
    final String displayStatus = isDelivered ? "LIVRÉ" : "EN ATTENTE";
    final Color statusColor = isDelivered ? Colors.green : Colors.orange;

    return GestureDetector(
      onTap: () => context.push('/profile/orders/detail', extra: order),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Commande #${(order['_id'] ?? '').toString().substring(0,8)}", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(DateFormat('dd MMM yyyy à HH:mm').format(date), 
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    displayStatus,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${(order['items'] as List).length} article(s)", 
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
                Text("\$${total.toStringAsFixed(2)}", 
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF283593))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 60, color: Colors.orange),
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _fetchOrders, child: const Text("Réessayer")),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("Aucun achat trouvé.", style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}
