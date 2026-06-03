import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:provider/provider.dart';

class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({
    required this.navigationShell,
    super.key,
  });

  // ─── Palette ──────────────────────────────────────────────────────────────
  static const Color _navy      = Color(0xFF0D1B4B);
  static const Color _accent    = Color(0xFF4A6CF7);
  static const Color _textMuted = Color(0xFF8A94B2);

  @override
  Widget build(BuildContext context) {
    final int currentIndex = navigationShell.currentIndex;

    final List<_NavItem> items = [
      const _NavItem(
        label: 'Accueil',
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
      ),
      const _NavItem(
        label: 'Catégories',
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
      ),
      const _NavItem(
        label: 'Panier',
        icon: Icons.shopping_bag_outlined,
        activeIcon: Icons.shopping_bag_rounded,
        isCenter: true,
      ),
      const _NavItem(
        label: 'Messages',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        hasBadge: true,
      ),
      const _NavItem(
        label: 'Profil',
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
      ),
    ];

    // Hauteur totale barre : 68 (barre) + 22 (padding bas) = 90
    // Injectée dans le MediaQuery pour que les Scrollable réservent l'espace.
    const double navBarTotalHeight = 90.0;

    return Scaffold(
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: MediaQuery.of(context).padding.copyWith(
            bottom: MediaQuery.of(context).padding.bottom + navBarTotalHeight,
          ),
        ),
        child: navigationShell,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Consumer<SocketProvider>(
          builder: (context, socket, _) {
            return Container(
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withOpacity(0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: _accent.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final bool isSelected = currentIndex == index;
                  final int badgeCount = item.hasBadge ? socket.unreadCount : 0;

                  return _NavBarItem(
                    item: item,
                    isSelected: isSelected,
                    badgeCount: badgeCount,
                    onTap: () => navigationShell.goBranch(index),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Modèle d'item ────────────────────────────────────────────────────────────

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isCenter;
  final bool hasBadge;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.isCenter = false,
    this.hasBadge = false,
  });
}

// ─── Widget item de la nav bar ────────────────────────────────────────────────

class _NavBarItem extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;

  static const Color _navy      = Color(0xFF0D1B4B);
  static const Color _accent    = Color(0xFF4A6CF7);
  static const Color _textMuted = Color(0xFF8A94B2);

  const _NavBarItem({
    required this.item,
    required this.isSelected,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Bouton central (Panier)
    if (item.isCenter) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isSelected
                  ? [_navy, const Color(0xFF2A4099)]
                  : [_accent, const Color(0xFF6B8EFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? _navy : _accent).withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            isSelected ? item.activeIcon : item.icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      );
    }

    // Items normaux
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accent.withOpacity(0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSelected ? item.activeIcon : item.icon,
                    size: 22,
                    color: isSelected ? _accent : _textMuted,
                  ),
                ),

                // Badge non lu
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 3),

            // Label animé
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _accent : _textMuted,
              ),
              child: Text(item.label),
            ),

            const SizedBox(height: 3),

            // Point indicateur actif
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: isSelected ? 4 : 0,
              height: isSelected ? 4 : 0,
              decoration: const BoxDecoration(
                color: Color(0xFF4A6CF7),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}