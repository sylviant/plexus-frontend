import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';
import 'package:go_router/go_router.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String? otherName; 
  final String? productTitle;
  final String? orderId; 

  const ChatScreen({
    required this.conversationId,
    this.otherName,
    this.productTitle,
    this.orderId,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = <ChatMessage>[];
  late SocketProvider _socketProvider;
  StreamSubscription? _messageSubscription;
  
  Map<String, dynamic>? _currentOrder; 
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _socketProvider = Provider.of<SocketProvider>(context, listen: false);
    _socketProvider.enterChat(widget.conversationId);
    _loadHistory();
    _listenToStream();
    _refreshOrder();
  }

  Future<void> _refreshOrder() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    
    try {
      String? idToFetch = widget.orderId;
      if (idToFetch == null || idToFetch.isEmpty) {
        final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/orders/conversation/${widget.conversationId}'))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final order = json.decode(res.body);
          if (order != null) idToFetch = order['_id'];
        }
      }

      if (idToFetch != null) {
        final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/orders/$idToFetch'))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final order = json.decode(res.body);
          if (mounted) setState(() { _currentOrder = order; });
        }
      }
    } catch (e) {
      debugPrint("Erreur refresh: $e");
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _confirmReceipt() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final orderId = _currentOrder?['_id'] ?? widget.orderId;
    if (orderId == null) return;

    try {
      final res = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/orders/$orderId/receive'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'senderName': auth.currentUser?.firstName ?? 'L\'acheteur'}),
      );

      if (res.statusCode == 200) {
        final systemMsg = ChatMessage(
          text: "📢 SYSTÈME : Réception confirmée. Fonds libérés.",
          user: ChatUser(id: 'system', firstName: 'PLEXUS'),
          createdAt: DateTime.now(),
        );
        _socketProvider.sendMessage(systemMsg, widget.conversationId, 'Système');
        _refreshOrder();
      }
    } catch (e) { debugPrint("Erreur réception: $e"); }
  }

  Future<void> _updateStatus(String newStatus, String msgText, {double? shippingFee}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final orderId = _currentOrder?['_id'] ?? widget.orderId;
    if (orderId == null) return;

    try {
      final Map<String, dynamic> body = {
        'status': newStatus,
        'senderName': auth.currentUser?.firstName ?? 'Utilisateur PLEXUS',
      };
      if (shippingFee != null) body['shippingFee'] = shippingFee;

      final res = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/orders/$orderId/status'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (res.statusCode == 200) {
        final systemMsg = ChatMessage(
          text: "📢 SYSTÈME : $msgText",
          user: ChatUser(id: 'system', firstName: 'PLEXUS'),
          createdAt: DateTime.now(),
        );
        _socketProvider.sendMessage(systemMsg, widget.conversationId, 'Système');
        final updatedData = json.decode(res.body);
        setState(() {
          _messages.insert(0, systemMsg);
          _currentOrder = updatedData;
        });
      }
    } catch (e) { debugPrint("Erreur statut: $e"); }
  }

  void _showShippingForm() {
    final feeC = TextEditingController();
    final modeC = TextEditingController();
    final timeC = TextEditingController();
    final trackingC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Offre de Livraison", style: TextStyle(color: Color(0xFF283593), fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: feeC, decoration: const InputDecoration(labelText: "Frais de livraison (\$)"), keyboardType: TextInputType.number),
              TextField(controller: modeC, decoration: const InputDecoration(labelText: "Mode (ex: DHL, Main propre)")),
              TextField(controller: timeC, decoration: const InputDecoration(labelText: "Délai (ex: 48h, 5 jours)")),
              TextField(controller: trackingC, decoration: const InputDecoration(labelText: "N° Suivi (optionnel)")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final double? fee = double.tryParse(feeC.text);
              String msg = "📦 *OFFRE DE LIVRAISON* :\n"
                  "• Frais: ${feeC.text}\$\n"
                  "• Mode: ${modeC.text}\n"
                  "• Délai: ${timeC.text}";
              if (trackingC.text.isNotEmpty) msg += "\n• Suivi: ${trackingC.text}";
              _updateStatus("WAITING_BUYER_CONFIRMATION", msg, shippingFee: fee);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF283593)),
            child: const Text("Envoyer l'offre"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).currentUser;
    if (currentUser == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherName ?? 'Journal de Transaction', style: const TextStyle(color: Color(0xFF283593), fontSize: 14, fontWeight: FontWeight.bold)),
            if (widget.productTitle != null) 
              Text(widget.productTitle!, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
        actions: [
          IconButton(
            icon: _isRefreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 20),
            onPressed: _refreshOrder,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_currentOrder != null) _buildActionPanel(currentUser),
          Expanded(
            child: DashChat(
              currentUser: currentUser,
              onSend: (ChatMessage m) {}, // Désactivé
              messages: _messages,
              // --- SUPPRESSION DU CHAMP DE SAISIE ---
              inputOptions: const InputOptions(
                sendOnEnter: false,
                inputDisabled: true, // Désactive le champ texte
              ),
              messageOptions: const MessageOptions(
                currentUserContainerColor: Color(0xFF283593), 
                containerColor: Color(0xFFF1F1F1),
                showOtherUsersAvatar: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanel(ChatUser currentUser) {
    final bool isSeller = _currentOrder!['sellerId'] == currentUser.id;
    final String status = _currentOrder!['status'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFFE3F2FD),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text("STATUT: $status", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blueGrey)),
              ),
              if (isSeller) _buildSellerButtons(status),
              if (!isSeller) _buildBuyerButtons(status),
            ],
          ),
          if (!isSeller && _currentOrder!['discountAmount'] != null && (_currentOrder!['discountAmount'] as num) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                "🎁 Réduction Parrainage : -${(_currentOrder!['discountAmount'] as num).toStringAsFixed(2)}\$",
                style: const TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSellerButtons(String status) {
    if (status == "PENDING_SHIPPING") {
      return ElevatedButton(
        onPressed: _showShippingForm, 
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF283593), foregroundColor: Colors.white),
        child: const Text("OFFRE DE LIVRAISON", style: TextStyle(fontSize: 10))
      );
    }
    if (status == "PAID") {
      return ElevatedButton(
        onPressed: () => _updateStatus("SHIPPED", "Le vendeur a expédié votre colis !"),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
        child: const Text("MARQUER COMME EXPÉDIÉ", style: TextStyle(fontSize: 10)),
      );
    }
    if (status == "SHIPPED") {
      return ElevatedButton(
        onPressed: () => _updateStatus("DELIVERED_BY_SELLER", "Vendeur confirme la livraison. Attente acheteur."),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
        child: const Text("MARQUER COMME LIVRÉ", style: TextStyle(fontSize: 10)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBuyerButtons(String status) {
    if (status == "WAITING_BUYER_CONFIRMATION") {
      final dynamic rawFee = _currentOrder?['shippingFee'] ?? _currentOrder?['shipping_fee'] ?? _currentOrder?['fee'];
      final double fee = (rawFee != null) ? double.tryParse(rawFee.toString()) ?? 0.0 : 0.0;
      final dynamic rawTotal = _currentOrder?['totalAmount'] ?? 0.0;
      final double totalProduct = double.tryParse(rawTotal.toString()) ?? 0.0;
      final double baseFees = (totalProduct + fee) * 0.03;
      final double discount = _currentOrder?['discountAmount'] != null ? (_currentOrder!['discountAmount'] as num).toDouble() : 0.0;
      final double totalToPay = totalProduct + fee + (baseFees - discount);
      final bool isPriceLoaded = fee > 0 || (rawFee != null && rawFee.toString() == "0");

      return ElevatedButton(
        onPressed: !isPriceLoaded ? null : () {
          context.push('/cart/payment', extra: {
            'orderId': _currentOrder?['_id'],
            'title': "Paiement Commande PLEXUS",
            'price': totalToPay, 
            'sellerId': _currentOrder?['sellerId'],
            'sellerWallet': _currentOrder?['sellerWallet'] ?? '',
            'isShippingOnly': false,
          });
        },
        style: ElevatedButton.styleFrom(backgroundColor: !isPriceLoaded ? Colors.grey : Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12)),
        child: Text(!isPriceLoaded ? "ATTENTE PRIX..." : "ACCEPTER ET PAYER (${totalToPay.toStringAsFixed(2)}\$)", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      );
    }
    
    if (status == "SHIPPED" || status == "DELIVERED_BY_SELLER") {
      return Row(
        children: [
          ElevatedButton(
            onPressed: _confirmReceipt, 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text("CONFIRMER RÉCEPTION", style: TextStyle(fontSize: 10)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              context.push('/dispute', extra: _currentOrder);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text("LITIGE", style: TextStyle(fontSize: 10)),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _loadHistory() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/messages/${widget.conversationId}'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(data.map((m) => ChatMessage(
              text: m['text'],
              user: ChatUser(id: m['senderId'], firstName: m['senderName']),
              createdAt: DateTime.parse(m['createdAt']),
            )).toList().reversed);
          });
        }
      }
    } catch (e) { debugPrint("Erreur history: $e"); }
  }

  void _listenToStream() {
    _messageSubscription = _socketProvider.messageStream.listen((message) {
      if (mounted) {
        setState(() { _messages.insert(0, message); });
        if (message.text.contains("SYSTÈME") || message.text.contains("OFFRE DE LIVRAISON")) {
          _refreshOrder();
        }
      }
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _socketProvider.leaveChat(); 
    super.dispose();
  }
}
