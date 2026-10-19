import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:plexus/l10n/l10n.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  // ─── Palette ─────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _accent     = Color(0xFF00B4D8);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final socket = Provider.of<SocketProvider>(context);

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: _primary.withOpacity(0.08),
        title: Text(
          l10n.messages,
          style: TextStyle(
            color: _textMain,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border, width: 1.2),
                ),
                child: const Icon(Icons.refresh_rounded,
                    size: 16, color: _textMain),
              ),
              onPressed: () {
                if (auth.currentUser != null) {
                  socket.loadConversations(auth.currentUser!.id);
                }
              },
            ),
          ),
        ],
      ),
      body: Consumer<SocketProvider>(
        builder: (context, socket, child) {
          final conversationsList =
              socket.conversations.entries.toList();

          conversationsList.sort((a, b) {
            final DateTime dateA = a.value['message'].createdAt;
            final DateTime dateB = b.value['message'].createdAt;
            return dateB.compareTo(dateA);
          });

          return Column(
            children: [
              // ── Offline banner ──────────────────────────────────
              if (!socket.isConnected)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF2F2),
                    border: Border(
                        bottom: BorderSide(
                            color: Color(0xFFFECACA), width: 1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          size: 14, color: Color(0xFFEF4444)),
                      SizedBox(width: 8),
                      Text(
                        l10n.modeHorsLigneServeurIntrouvable,
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── List ─────────────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  children: [
                    // Support tile
                    _buildSupportTile(context),

                    const SizedBox(height: 8),

                    if (conversationsList.isEmpty)
                      _buildEmptyState()
                    else ...[
                      // Section label
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(2, 12, 2, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 13,
                              decoration: BoxDecoration(
                                color: _primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.conversationsRecentes,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _textSub,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...conversationsList.map((entry) {
                        final roomId = entry.key;
                        if (roomId == "3")
                          return const SizedBox.shrink();

                        final info = entry.value;
                        final lastMsg = info['message'];
                        final String displayName = info['name'];

                        return _buildConversationTile(
                            context, roomId, displayName, lastMsg);
                      }),
                    ],
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_accent, Color(0xFF0081A7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.support_agent_rounded,
              color: Colors.white, size: 24),
        ),
        title: Text(
          l10n.supportPlexus,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _textMain,
          ),
        ),
        subtitle: Text(
          l10n.assistantIaDisponible24h24,
          style: TextStyle(
              color: _accent, fontSize: 12, fontWeight: FontWeight.w500),
        ),
        trailing: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border, width: 1),
          ),
          child: const Icon(Icons.arrow_forward_ios_rounded,
              size: 12, color: _textSub),
        ),
        // REDIRECTION VERS L'IA ASSISTANCE MODIFIÉE ICI
        onTap: () => context.push('/ai-chat'),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildConversationTile(
      BuildContext context, String roomId, String name, dynamic lastMsg) {
    final String initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    final String time =
        DateFormat.jm().format(lastMsg.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _primary.withOpacity(0.8),
                _primaryMid,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _textMain,
          ),
        ),
        subtitle: Text(
          trChatText(lastMsg.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _textSub, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              time,
              style: const TextStyle(
                fontSize: 11,
                color: _textSub,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        onTap: () => context.push(
          '/messages/chat/$roomId',
          extra: {
            'otherName': name,
            'productTitle': l10n.discussion,
          },
        ),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _primary.withOpacity(0.07),
                    blurRadius: 20,
                  )
                ],
              ),
              child: const Icon(Icons.chat_outlined,
                  size: 36, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.aucuneDiscussionActive,
              style: TextStyle(
                  color: _textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.vosEchangesAvecLesVendeurs,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _textSub, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
