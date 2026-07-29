import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:native_glass_navbar/native_glass_navbar.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:provider/provider.dart';

// ─── IMPORTANT : dans main.dart, définissez la couleur primaire PLEXUS ────────
// MaterialApp(
//   theme: ThemeData(
//     colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF4A6CF7)),
//   ),
// )
// NativeGlassNavBar utilise Theme.of(context).colorScheme.primary
// comme couleur de l'onglet sélectionné — pas de paramètre tint/tintColor.

class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({
    required this.navigationShell,
    super.key,
  });

  static const Color _accent = Color(0xFF4A6CF7);

  @override
  Widget build(BuildContext context) {
    final int currentIndex = navigationShell.currentIndex;

    return Consumer<SocketProvider>(
      builder: (context, socket, _) {
        return Scaffold(
          // extendBody OBLIGATOIRE : le contenu remonte sous la barre native
          extendBody: true,
          body: navigationShell,

          bottomNavigationBar: NativeGlassNavBar(
            currentIndex: currentIndex,
            onTap: (index) => navigationShell.goBranch(index),

            // ✅ API exacte 1.0.2 : label + symbol uniquement
            tabs: const [
              NativeGlassNavBarItem(label: 'Accueil',    symbol: 'house'),
              NativeGlassNavBarItem(label: 'Catégories', symbol: 'square.grid.2x2'),
              NativeGlassNavBarItem(label: 'Panier',     symbol: 'bag'),
              NativeGlassNavBarItem(label: 'Messages',   symbol: 'message'),
              NativeGlassNavBarItem(label: 'Profil',     symbol: 'person'),
            ],

            // Fallback Flutter pour Android + iOS < 26
            fallback: _FlutterFallbackNavBar(
              currentIndex: currentIndex,
              accent:       _accent,
              badgeCount:   socket.unreadCount,
              onTap:        (i) => navigationShell.goBranch(i),
            ),
          ),
        );
      },
    );
  }
}

// ─── Fallback Flutter pur (Android + iOS < 26) ────────────────────────────────
// Liquid Glass en BackdropFilter — même visuel que CNTabBar
// Barre compacte (56px) positionnée plus bas

class _FlutterFallbackNavBar extends StatelessWidget {
  final int    currentIndex;
  final Color  accent;
  final int    badgeCount;
  final void Function(int) onTap;

  const _FlutterFallbackNavBar({
    required this.currentIndex,
    required this.accent,
    required this.badgeCount,
    required this.onTap,
  });

  static const List<_FbItem> _items = [
    _FbItem(label: 'Accueil',    icon: Icons.home_outlined,              activeIcon: Icons.home_rounded),
    _FbItem(label: 'Catégories', icon: Icons.grid_view_outlined,          activeIcon: Icons.grid_view_rounded),
    _FbItem(label: 'Panier',     icon: Icons.shopping_bag_outlined,       activeIcon: Icons.shopping_bag_rounded, isCenter: true),
    _FbItem(label: 'Messages',   icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded,  hasBadge: true),
    _FbItem(label: 'Profil',     icon: Icons.person_outline_rounded,      activeIcon: Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.10)
                  : Colors.white.withOpacity(0.55),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.18)
                    : Colors.white.withOpacity(0.85),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color:        Colors.black.withOpacity(isDark ? 0.30 : 0.10),
                  blurRadius:   28,
                  spreadRadius: -4,
                  offset:       const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_items.length, (i) {
                return _FbNavItem(
                  item:       _items[i],
                  isSelected: currentIndex == i,
                  accent:     accent,
                  badgeCount: _items[i].hasBadge ? badgeCount : 0,
                  isDark:     isDark,
                  onTap:      () => onTap(i),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _FbNavItem extends StatefulWidget {
  final _FbItem      item;
  final bool         isSelected;
  final Color        accent;
  final int          badgeCount;
  final bool         isDark;
  final VoidCallback onTap;

  const _FbNavItem({
    required this.item,
    required this.isSelected,
    required this.accent,
    required this.badgeCount,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_FbNavItem> createState() => _FbNavItemState();
}

class _FbNavItemState extends State<_FbNavItem>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<double>   _dip;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 200),
    );
    _dip = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 2.0).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 2.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 65),
    ]).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final item       = widget.item;
    final accent     = widget.accent;
    final isDark     = widget.isDark;

    final Color iconC = isSelected ? accent : (isDark ? Colors.white.withOpacity(0.45) : Colors.black.withOpacity(0.35));
    final Color lblC  = isSelected ? accent : (isDark ? Colors.white.withOpacity(0.40) : Colors.black.withOpacity(0.32));

    // ── Bouton central Panier ─────────────────────────────────────────────
    if (item.isCenter) {
      return GestureDetector(
        onTap: () { _ctrl.forward(from: 0); widget.onTap(); },
        child: AnimatedBuilder(
          animation: _dip,
          builder: (_, child) => Transform.translate(offset: Offset(0, _dip.value), child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isSelected
                    ? [const Color(0xFF0D1B4B), const Color(0xFF2A4099)]
                    : [accent, const Color(0xFF6B8EFF)],
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color:      (isSelected ? const Color(0xFF0D1B4B) : accent).withOpacity(0.40),
                  blurRadius: 12,
                  offset:     const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                key:   ValueKey(isSelected),
                color: Colors.white,
                size:  20,
              ),
            ),
          ),
        ),
      );
    }

    // ── Items normaux ─────────────────────────────────────────────────────
    return GestureDetector(
      onTap: () { _ctrl.forward(from: 0); widget.onTap(); },
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _dip,
        builder: (_, child) => Transform.translate(offset: Offset(0, _dip.value), child: child),
        child: SizedBox(
          width: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Pill de sélection
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accent.withOpacity(isDark ? 0.20 : 0.11)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                      child: Icon(
                        isSelected ? item.activeIcon : item.icon,
                        key:   ValueKey(isSelected),
                        size:  20,
                        color: iconC,
                      ),
                    ),
                  ),
                  // Badge messages
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: -3, right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color:         const Color(0xFFE53935),
                          borderRadius:  BorderRadius.circular(9),
                          border:        Border.all(color: Colors.white.withOpacity(0.9), width: 1.5),
                        ),
                        child: Text(
                          widget.badgeCount > 99 ? '99+' : widget.badgeCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 1),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                style: TextStyle(
                  fontSize:   9,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color:      lblC,
                ),
                child: Text(item.label),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                width:  isSelected ? 3.0 : 0.0,
                height: isSelected ? 3.0 : 0.0,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FbItem {
  final String   label;
  final IconData icon;
  final IconData activeIcon;
  final bool     isCenter;
  final bool     hasBadge;
  const _FbItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.isCenter = false,
    this.hasBadge = false,
  });
}