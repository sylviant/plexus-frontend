import 'package:flutter/material.dart';
import 'package:plexus/core/models/user_type.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:provider/provider.dart';

class UserTypeSelectionScreen extends StatefulWidget {
  const UserTypeSelectionScreen({super.key});

  @override
  State<UserTypeSelectionScreen> createState() =>
      _UserTypeSelectionScreenState();
}

class _UserTypeSelectionScreenState extends State<UserTypeSelectionScreen>
    with SingleTickerProviderStateMixin {
  // ─── Palette ─────────────────────────────────────────────────────────────
  static const Color _navy = Color(0xFF0D1B4B);
  static const Color _navyMid = Color(0xFF1A2E6E);
  static const Color _accent = Color(0xFF4A6CF7);
  static const Color _surface = Color(0xFFF4F6FF);
  static const Color _textMuted = Color(0xFF8A94B2);

  UserType? _selectedType;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 40, end: 0).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ─── BACKEND (inchangé) ─────────────────────────────────────────────────
  void _onSelectType(UserType type) {
    setState(() => _selectedType = type);
    Provider.of<UserProvider>(context, listen: false).setUserType(type);
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        children: [
          // ── Fond dégradé en haut ────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.42,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_navy, _navyMid, Color(0xFF2A4099)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  // Cercles décoratifs
                  Positioned(
                    top: -40,
                    right: -30,
                    child: _circle(160, Colors.white, 0.05),
                  ),
                  Positioned(
                    top: 30,
                    right: 50,
                    child: _circle(60, _accent, 0.15),
                  ),
                  Positioned(
                    bottom: 30,
                    left: -20,
                    child: _circle(100, Colors.white, 0.04),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu ──────────────────────────────────────────────────────
          SafeArea(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) => FadeTransition(
                opacity: _fadeAnim,
                child: Transform.translate(
                  offset: Offset(0, _slideAnim.value),
                  child: child,
                ),
              ),
              child: Column(
                children: [
                  // ── En-tête ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 36, 28, 0),
                    child: Column(
                      children: [
                        // Logo / icône de marque
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1.5),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Bienvenue sur Plexus",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Comment souhaitez-vous utiliser\nl'application ?",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Cartes de sélection ──────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          _buildTypeCard(
                            type: UserType.client,
                            icon: Icons.shopping_bag_outlined,
                            title: "Je suis un Client",
                            subtitle:
                                "Parcourez et achetez des articles auprès de vendeurs vérifiés.",
                            accentColor: _accent,
                            features: const [
                              "Accès à tous les produits",
                              "Suivi de commandes",
                              "Favoris & listes",
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTypeCard(
                            type: UserType.seller,
                            icon: Icons.store_outlined,
                            title: "Je suis un Vendeur",
                            subtitle:
                                "Publiez vos articles et gérez votre boutique en ligne.",
                            accentColor: const Color(0xFF00B386),
                            features: const [
                              "Tableau de bord vendeur",
                              "Gestion des commandes",
                              "Retrait des gains",
                            ],
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CARTE TYPE UTILISATEUR ───────────────────────────────────────────────
  Widget _buildTypeCard({
    required UserType type,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<String> features,
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () => _onSelectType(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFFEBEFF8),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? accentColor.withOpacity(0.12)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icône avec fond coloré
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor
                        : accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : accentColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? accentColor : _navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                // Indicateur de sélection
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? accentColor : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? accentColor
                          : const Color(0xFFD0D5E8),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),

            if (isSelected) ...[
              const SizedBox(height: 18),
              Container(
                height: 1,
                color: accentColor.withOpacity(0.1),
              ),
              const SizedBox(height: 16),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 11, color: accentColor),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        f,
                        style: TextStyle(
                          fontSize: 12,
                          color: _navy.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _circle(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
      ),
    );
  }
}