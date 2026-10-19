import 'package:flutter/material.dart';
import 'package:plexus/l10n/l10n.dart';

class CategoryList extends StatelessWidget {
  final Function(String) onCategorySelected;
  final String selectedCategory;

  const CategoryList({
    required this.onCategorySelected,
    required this.selectedCategory,
    super.key,
  });

  // ─── Palette (cohérente avec l'app) ──────────────────────────────────────
  static const Color _navy = Color(0xFF0D1B4B);
  static const Color _accent = Color(0xFF4A6CF7);

  @override
  Widget build(BuildContext context) {
    // On garde les icônes en secours, mais on privilégie l'affichage d'images
    final List<Map<String, dynamic>> categories = [
      {'name': 'Tout', 'icon': Icons.grid_view_rounded, 'image': 'tout.png'},
      {'name': 'Maison', 'icon': Icons.home_outlined, 'image': 'maison.png'},
      {'name': 'Beauté', 'icon': Icons.spa_outlined, 'image': 'beaute.png'},
      {'name': 'Électronique', 'icon': Icons.devices_other_outlined, 'image': 'electronique.png'},
      {'name': 'Mode', 'icon': Icons.checkroom_outlined, 'image': 'mode.png'},
      {'name': 'Livres', 'icon': Icons.book_outlined, 'image': 'livres.png'},
      {'name': 'Sports', 'icon': Icons.sports_soccer_outlined, 'image': 'sports.png'},
      {'name': 'Alimentation', 'icon': Icons.restaurant_outlined, 'image': 'alimentation.png'},
      {'name': 'Automobile', 'icon': Icons.directions_car_outlined, 'image': 'automobile.png'},
      {'name': 'Jouets', 'icon': Icons.toys_outlined, 'image': 'jouets.png'},
    ];

    return Container(
      height: 100,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final String name = category['name'];
          final bool isSelected = selectedCategory == name;

          return GestureDetector(
            onTap: () => onCategorySelected(name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? _navy : const Color(0xFFF4F6FF),
                borderRadius: BorderRadius.circular(50),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _navy.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icône / image dans un petit cercle
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.15)
                          : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/categories/${category['image']}',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          category['icon'] as IconData,
                          size: 16,
                          color: isSelected ? Colors.white : _accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    trData(name),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF5A6490),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}