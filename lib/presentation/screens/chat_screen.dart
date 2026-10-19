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
import 'package:plexus/l10n/l10n.dart';

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

  // ─── Palette ─────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _socketProvider =
        Provider.of<SocketProvider>(context, listen: false);
    _socketProvider.enterChat(widget.conversationId);
    _loadHistory();
    _listenToStream();
    _refreshOrder();
  }

  // ─── Backend logic (unchanged) ───────────────────────────────────────────

  Future<void> _refreshOrder() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      String? idToFetch = (widget.orderId != null && widget.orderId!.isNotEmpty)
          ? widget.orderId
          : null;

      // Si orderId non fourni, on interroge le backend via le conversationId
      if (idToFetch == null) {
        final res = await http
            .get(Uri.parse(
            '${ApiConfig.baseUrl}/orders/conversation/${widget.conversationId}'))
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final dynamic decoded = json.decode(res.body);
          if (decoded != null) {
            // La route peut retourner un objet direct ou un tableau
            if (decoded is List && decoded.isNotEmpty) {
              idToFetch = decoded.first['_id'];
            } else if (decoded is Map<String, dynamic>) {
              idToFetch = decoded['_id'];
            }
          }
        }
      }

      // Une fois l'ID connu, on charge les détails complets de la commande
      if (idToFetch != null && idToFetch.isNotEmpty) {
        final res = await http
            .get(Uri.parse('${ApiConfig.baseUrl}/orders/$idToFetch'))
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final order = json.decode(res.body);
          if (mounted) {
            setState(() => _currentOrder = order);
          }
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
        body: json.encode({
          'senderName': auth.currentUser?.firstName ?? l10n.acheteur
        }),
      );

      if (res.statusCode == 200) {
        final systemMsg = ChatMessage(
          text: "📢 SYSTÈME : Réception confirmée. Fonds libérés.",
          user: ChatUser(id: 'system', firstName: 'PLEXUS'),
          createdAt: DateTime.now(),
        );
        _socketProvider.sendMessage(
            systemMsg, widget.conversationId, 'Système');
        _refreshOrder();
      }
    } catch (e) {
      debugPrint("Erreur réception: $e");
    }
  }

  Future<void> _updateStatus(String newStatus, String msgText,
      {double? shippingFee}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final orderId = _currentOrder?['_id'] ?? widget.orderId;
    if (orderId == null) return;

    try {
      final Map<String, dynamic> body = {
        'status': newStatus,
        'senderName':
        auth.currentUser?.firstName ?? l10n.utilisateurPlexus,
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
        _socketProvider.sendMessage(
            systemMsg, widget.conversationId, 'Système');
        final updatedData = json.decode(res.body);
        setState(() {
          _messages.insert(0, systemMsg);
          _currentOrder = updatedData;
        });
      }
    } catch (e) {
      debugPrint("Erreur statut: $e");
    }
  }

  // NOUVEAU — remplace l'ancien _showShippingForm : les frais de livraison
  // sont déjà inclus dans le paiement initial (voir computeShippingFee côté
  // backend), donc le vendeur n'a plus qu'à indiquer transporteur + suivi.
  static const List<String> _carriers = [
    'Bufalo Express', 'General Express', 'Guichet Express', 'DHL',
    'UPS', 'FedEx', 'Chronopost', 'La Poste', 'Main propre', 'Autre',
  ];

  Future<void> _markAsShipped() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final orderId = _currentOrder?['_id'] ?? widget.orderId;
    if (orderId == null) return;

    final trackingC = TextEditingController();
    String selectedCarrier = _carriers.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  color: _primary, size: 20),
              SizedBox(width: 10),
              Text(
                l10n.expedierLeColis,
                style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.transporteur,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _textSub)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedCarrier,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _carriers
                      .map((c) => DropdownMenuItem(value: c, child: Text(trData(c))))
                      .toList(),
                  onChanged: (value) => setDialogState(
                          () => selectedCarrier = value ?? selectedCarrier),
                ),
                const SizedBox(height: 12),
                _dialogField(
                    controller: trackingC,
                    label: l10n.nSuiviOptionnel,
                    icon: Icons.qr_code_outlined),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.annuler,
                  style: TextStyle(color: _textSub)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(l10n.confirmerLExpedition,
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final res = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/orders/$orderId/ship'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'trackingNumber': trackingC.text,
          'shippingCarrier': selectedCarrier,
        }),
      );

      if (res.statusCode == 200) {
        String msg = "📦 *COLIS EXPÉDIÉ* :\n• Transporteur: $selectedCarrier";
        if (trackingC.text.isNotEmpty) msg += "\n• Suivi: ${trackingC.text}";
        final systemMsg = ChatMessage(
          text: "📢 SYSTÈME : $msg",
          user: ChatUser(id: 'system', firstName: 'PLEXUS'),
          createdAt: DateTime.now(),
        );
        _socketProvider.sendMessage(
            systemMsg, widget.conversationId, 'Système');
        final updatedData = json.decode(res.body);
        setState(() {
          _messages.insert(0, systemMsg);
          _currentOrder = updatedData;
        });
      }
    } catch (e) {
      debugPrint("Erreur expédition: $e");
    }
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: _textMain, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
        const TextStyle(color: _textSub, fontSize: 13),
        prefixIcon: Icon(icon, color: _textSub, size: 18),
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          const BorderSide(color: _border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          const BorderSide(color: _border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          const BorderSide(color: _primaryMid, width: 2),
        ),
      ),
    );
  }

  Future<void> _loadHistory() async {
    try {
      final response = await http.get(Uri.parse(
          '${ApiConfig.baseUrl}/messages/${widget.conversationId}'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(data
                .map((m) => ChatMessage(
              text: m['text'],
              user: ChatUser(
                  id: m['senderId'],
                  firstName: m['senderName']),
              createdAt: DateTime.parse(m['createdAt']),
            ))
                .toList()
                .reversed);
          });
        }
      }
    } catch (e) {
      debugPrint("Erreur history: $e");
    }
  }

  void _listenToStream() {
    _messageSubscription =
        _socketProvider.messageStream.listen((message) {
          if (mounted) {
            setState(() => _messages.insert(0, message));
            if (message.text.contains("SYSTÈME") ||
                message.text.contains("COLIS EXPÉDIÉ")) {
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

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentUser =
        Provider.of<AuthProvider>(context).currentUser;
    if (currentUser == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: _primary.withOpacity(0.08),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border, width: 1.2),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 15, color: _textMain),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primary, _primaryMid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (widget.otherName ?? 'P')
                      .substring(0, 1)
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherName ?? l10n.journalDeTransaction,
                    style: const TextStyle(
                      color: _textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.productTitle != null)
                    Text(
                      widget.productTitle!,
                      style: const TextStyle(
                          color: _textSub, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _primary),
              )
                  : Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: _border, width: 1.2),
                ),
                child: const Icon(Icons.refresh_rounded,
                    size: 16, color: _textMain),
              ),
              onPressed: _refreshOrder,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_currentOrder != null)
            _buildActionPanel(currentUser),
          Expanded(
            child: DashChat(
              currentUser: currentUser,
              onSend: (ChatMessage m) {},
              messages: _messages.map(_localizedMessage).toList(),
              inputOptions: const InputOptions(
                sendOnEnter: false,
                inputDisabled: true,
              ),
              messageOptions: MessageOptions(
                currentUserContainerColor: _primary,
                containerColor: Colors.white,
                showOtherUsersAvatar: true,
                messagePadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                borderRadius: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Affichage : traduit les messages système (stockés en français) selon la langue du téléphone.
  ChatMessage _localizedMessage(ChatMessage m) {
    final String t = trChatText(m.text);
    if (t == m.text) return m;
    return ChatMessage(
      text: t,
      user: m.user,
      createdAt: m.createdAt,
      medias: m.medias,
      customProperties: m.customProperties,
    );
  }

  // ─── Action panel ─────────────────────────────────────────────────────────

  Widget _buildActionPanel(ChatUser currentUser) {
    final bool isSeller =
        _currentOrder!['sellerId'] == currentUser.id;
    final String status = _currentOrder!['status'] ?? '';

    // Status color
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'PENDING_SHIPPING':
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case 'PAID':
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.payments_outlined;
        break;
      case 'SHIPPED':
        statusColor = const Color(0xFF3B82F6);
        statusIcon = Icons.local_shipping_outlined;
        break;
      case 'DELIVERED_BY_SELLER':
        statusColor = const Color(0xFF8B5CF6);
        statusIcon = Icons.inventory_2_outlined;
        break;
      case 'WAITING_BUYER_CONFIRMATION':
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.pending_actions_outlined;
        break;
      case 'COMPLETED':
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      default:
        statusColor = _textSub;
        statusIcon = Icons.info_outline_rounded;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: _border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status badge row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: statusColor.withOpacity(0.25),
                      width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      status.replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),

              // Referral discount badge
              if (!isSeller &&
                  _currentOrder!['discountAmount'] != null &&
                  (_currentOrder!['discountAmount'] as num) > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF10B981)
                            .withOpacity(0.25),
                        width: 1),
                  ),
                  child: Text(
                    '🎁 -${(_currentOrder!['discountAmount'] as num).toStringAsFixed(2)}\$',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Action buttons
              if (isSeller) _buildSellerButtons(status),
              if (!isSeller) _buildBuyerButtons(status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSellerButtons(String status) {
    // NOUVEAU — le frais de livraison est déjà payé à la commande
    // (voir computeShippingFee), donc PENDING_SHIPPING et PAID mènent
    // tous deux directement à l'expédition : plus d'étape "offre" séparée.
    if (status == "PENDING_SHIPPING" || status == "PAID") {
      return _ActionButton(
        label: l10n.marquerExpedie,
        icon: Icons.send_rounded,
        color: const Color(0xFFF59E0B),
        onPressed: _markAsShipped,
      );
    }
    if (status == "SHIPPED") {
      return _ActionButton(
        label: l10n.marquerLivre,
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF64748B),
        onPressed: () => _updateStatus("DELIVERED_BY_SELLER",
            "Vendeur confirme la livraison. Attente acheteur."),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBuyerButtons(String status) {
    // LEGACY — plus jamais atteint par de nouvelles commandes (le frais est
    // maintenant payé dès la commande initiale). Conservé uniquement pour
    // que d'éventuelles commandes déjà bloquées dans cet état puissent
    // encore être finalisées par l'acheteur.
    if (status == "WAITING_BUYER_CONFIRMATION") {
      final dynamic rawFee = _currentOrder?['shippingFee'] ??
          _currentOrder?['shipping_fee'] ??
          _currentOrder?['fee'];
      final double fee = (rawFee != null)
          ? double.tryParse(rawFee.toString()) ?? 0.0
          : 0.0;
      final dynamic rawTotal =
          _currentOrder?['totalAmount'] ?? 0.0;
      final double totalProduct =
          double.tryParse(rawTotal.toString()) ?? 0.0;
      final double baseFees = (totalProduct + fee) * 0.03;
      final double discount =
      _currentOrder?['discountAmount'] != null
          ? (_currentOrder!['discountAmount'] as num).toDouble()
          : 0.0;
      final double totalToPay =
          totalProduct + fee + (baseFees - discount);
      final bool isPriceLoaded = fee > 0 ||
          (rawFee != null && rawFee.toString() == "0");

      return _ActionButton(
        label: !isPriceLoaded
            ? l10n.attentePrix
            : l10n.payerLivraison('${fee.toStringAsFixed(2)}'),
        icon: isPriceLoaded
            ? Icons.local_shipping_outlined
            : Icons.hourglass_top_rounded,
        color: isPriceLoaded
            ? const Color(0xFF10B981)
            : const Color(0xFF94A3B8),
        onPressed: !isPriceLoaded
            ? null
            : () => context.push('/cart/payment', extra: {
          'orderId': _currentOrder?['_id'],
          'title': 'Frais de Livraison PLEXUS',
          'price': fee,
          'sellerId': _currentOrder?['sellerId'],
          'sellerWallet':
          _currentOrder?['sellerWallet'] ?? '',
          'isShippingOnly': true,
        }),
      );
    }

    if (status == "SHIPPED" || status == "DELIVERED_BY_SELLER") {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            label: l10n.reception,
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF3B82F6),
            onPressed: _confirmReceipt,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'LITIGE',
            icon: Icons.gavel_rounded,
            color: const Color(0xFFEF4444),
            onPressed: () =>
                context.push('/dispute', extra: _currentOrder),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: disabled
              ? const Color(0xFFE2E8F0)
              : color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: disabled
              ? []
              : [
            BoxShadow(
              color: color.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: disabled
                    ? const Color(0xFF94A3B8)
                    : Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: disabled
                    ? const Color(0xFF94A3B8)
                    : Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}