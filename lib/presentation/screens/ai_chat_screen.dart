import 'package:flutter/material.dart';
import '../../core/models/ai_product.dart';
import '../../core/services/ai_chat_service.dart';
import '../widgets/product_card_widget.dart';

class _ChatBubble {
  final String role; // 'user' ou 'assistant'
  final String message;
  final List<AiProduct> products;

  _ChatBubble({
    required this.role,
    required this.message,
    this.products = const [],
  });
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiChatService _service = AiChatService();
  final List<_ChatBubble> _bubbles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Message de bienvenue
    _bubbles.add(_ChatBubble(
      role: 'assistant',
      message: 'Bonjour ! 👋 Décris-moi ce que tu cherches — couleur, prix, type de produit — et je te trouve les meilleures options.',
    ));
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _bubbles.add(_ChatBubble(role: 'user', message: text));
      _isLoading = true;
    });
    _scrollToBottom();

    final response = await _service.sendMessage(text);

    setState(() {
      _bubbles.add(_ChatBubble(
        role: 'assistant',
        message: response.message,
        products: response.products,
      ));
      _isLoading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToProduct(String productId) {
    // Adapte avec ton router existant
    // context.push('/product/$productId');
    // ou :
    Navigator.pushNamed(context, '/product', arguments: productId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple,
              child: Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assistant IA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text('Trouve ton produit idéal', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _bubbles.clear());
              _service.clearHistory();
              _bubbles.add(_ChatBubble(
                role: 'assistant',
                message: 'Nouvelle conversation ! Que cherches-tu ?',
              ));
            },
          )
        ],
      ),
      body: Column(
        children: [
          // Liste des messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _bubbles.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                // Indicateur de chargement
                if (_isLoading && index == _bubbles.length) {
                  return _buildTypingIndicator();
                }
                return _buildBubble(_bubbles[index]);
              },
            ),
          ),
          // Champ de saisie
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatBubble bubble) {
    final isUser = bubble.role == 'user';
    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // Bulle texte
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).primaryColor
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            bubble.message,
            style: TextStyle(
              color: isUser ? Colors.white : null,
              fontSize: 14,
            ),
          ),
        ),
        // Cartes produits (si présents)
        if (bubble.products.isNotEmpty) ...[
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: bubble.products.length,
              itemBuilder: (context, i) => ProductCardWidget(
                product: bubble.products[i],
                onTap: () => _navigateToProduct(bubble.products[i].productId),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => _dot(i)),
        ),
      ),
    );
  }

  Widget _dot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: Duration(milliseconds: 400 + index * 150),
      builder: (_, val, __) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(val),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Ex: téléphone rouge moins de 50 000 FCFA...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}