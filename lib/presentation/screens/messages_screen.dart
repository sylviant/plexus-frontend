import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final socket = Provider.of<SocketProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Discussions', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          // Bouton pour forcer le rechargement des messages
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (auth.currentUser != null) {
                socket.loadConversations(auth.currentUser!.id);
              }
            },
          ),
        ],
      ),
      body: Consumer<SocketProvider>(
        builder: (context, socket, child) {
          final conversationsList = socket.conversations.entries.toList();

          conversationsList.sort((a, b) {
            final DateTime dateA = a.value['message'].createdAt;
            final DateTime dateB = b.value['message'].createdAt;
            return dateB.compareTo(dateA);
          });

          return Column(
            children: [
              // Indicateur de statut de connexion
              if (!socket.isConnected)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.red[50],
                  child: const Text(
                    "🔴 Mode hors-ligne (Serveur introuvable)",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: [
                    _buildSupportTile(context),
                    const Divider(),

                    if (conversationsList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.chat_outlined, size: 50, color: Colors.grey),
                              SizedBox(height: 10),
                              Text('Aucune discussion active.', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    else
                      ...conversationsList.map((entry) {
                        final roomId = entry.key;
                        if (roomId == "3") return const SizedBox.shrink(); 

                        final info = entry.value;
                        final lastMsg = info['message'];
                        final String displayName = info['name'];

                        return _buildConversationTile(context, roomId, displayName, lastMsg);
                      }),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSupportTile(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.blue[50],
        child: const Icon(Icons.support_agent, color: Colors.blue, size: 30),
      ),
      title: const Text("Support PLEXUS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      subtitle: const Text("Assistant IA disponible 24h/24", style: TextStyle(color: Colors.blue, fontSize: 13)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: () => context.push('/messages/chat/3'), 
    );
  }

  Widget _buildConversationTile(BuildContext context, String roomId, String name, dynamic lastMsg) {
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[100],
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : "?", 
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      subtitle: Text(
        lastMsg.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: Text(
        DateFormat('HH:mm').format(lastMsg.createdAt),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      onTap: () {
        context.push(
          '/messages/chat/$roomId',
          extra: {
            'otherName': name,
            'productTitle': 'Discussion', 
          },
        );
      },
    );
  }
}
