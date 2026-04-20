import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:go_router/go_router.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({required this.order, super.key});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late String _status;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _status = widget.order['status']?.toString() ?? "PENDING_SHIPPING";
  }

  Future<void> _confirmReceipt() async {
    setState(() => _isUpdating = true);
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/orders/${widget.order['_id']}/receive'),
      );

      if (response.statusCode == 200) {
        setState(() => _status = "DELIVERED");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Merci ! Le vendeur a été payé."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Erreur réception: $e");
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(widget.order['createdAt'] ?? DateTime.now().toIso8601String());
    final List items = widget.order['items'] ?? [];
    final currentUser = Provider.of<AuthProvider>(context).currentUser;
    
    final bool isBuyer = currentUser?.id == widget.order['userId'];
    final bool isSeller = currentUser?.id == widget.order['sellerId'];

    const Color primaryBlue = Color(0xFF283593);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Détails de la commande'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statut de la commande
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: primaryBlue, size: 30),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Statut : $_status", style: const TextStyle(fontWeight: FontWeight.bold, color: primaryBlue)),
                      Text(DateFormat('dd/MM/yyyy').format(date)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // --- BOUTON DE CHAT AUTOMATISÉ ---
            ElevatedButton.icon(
              onPressed: () {
                // IMPORTANT : On passe le orderId pour activer le système auto
                context.push('/messages/chat/${widget.order['userId']}_${widget.order['sellerId']}', extra: {
                  'otherName': isSeller ? widget.order['buyerName'] : 'Vendeur',
                  'productTitle': items.isNotEmpty ? items[0]['title'] : 'Commande',
                  'orderId': widget.order['_id'], 
                });
              },
              icon: const Icon(Icons.chat),
              label: Text(isSeller ? "DISCUTER AVEC L'ACHETEUR" : "CONTACTER LE VENDEUR"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 30),

            const Text("Articles", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...items.map((item) => ListTile(
              title: Text(item['title'] ?? 'Produit'),
              trailing: Text("\$${item['price']}"),
            )),

            const Divider(height: 40),
            
            if (isBuyer && _status == 'SHIPPED')
              ElevatedButton(
                onPressed: _isUpdating ? null : _confirmReceipt,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
                child: const Text("J'AI BIEN REÇU LE COLIS"),
              ),
          ],
        ),
      ),
    );
  }
}
