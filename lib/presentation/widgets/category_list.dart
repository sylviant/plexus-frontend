import 'package:flutter/material.dart';

class CategoryList extends StatelessWidget {
  final Function(String) onCategorySelected;
  final String selectedCategory;

  const CategoryList({
    required this.onCategorySelected,
    required this.selectedCategory,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // On garde les icônes en secours, mais on privilégie l'affichage d'images
    final List<Map<String, dynamic>> categories = [
      {'name': 'Tout', 'icon': Icons.grid_view, 'image': 'tout.png'},
      {'name': 'Maison', 'icon': Icons.home_outlined, 'image': 'maison.png'},
      {'name': 'Beauté', 'icon': Icons.spa_outlined, 'image': 'beaute.png'},
      {'name': 'Électronique', 'icon': Icons.devices_other_outlined, 'image': 'electronique.png'},
      {'name': 'Mode', 'icon': Icons.checkroom_outlined, 'image': 'mode.png'},
      {'name': 'Livres', 'icon': Icons.book_outlined, 'image': 'livres.png'},
      {'name': 'Sports', 'icon': Icons.sports_soccer_outlined, 'image': 'sports.png'},
      {'name': 'Alimentation', 'icon': Icons.restaurant, 'image': 'alimentation.png'},
      {'name': 'Automobile', 'icon': Icons.directions_car, 'image': 'automobile.png'},
      {'name': 'Jouets', 'icon': Icons.toys, 'image': 'jouets.png'},
    ];

    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final String name = category['name'];
          final bool isSelected = selectedCategory == name;

          return GestureDetector(
            onTap: () => onCategorySelected(name),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
              child: Column(
                children: [
                  Container(
                    width: 55,
                    height: 55,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF283593).withOpacity(0.1) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF283593) : Colors.transparent,
                        width: 1.5
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/categories/${category['image']}',
                        fit: BoxFit.cover,
                        // Si l'image n'existe pas dans les assets, on affiche l'icône
                        errorBuilder: (context, error, stackTrace) => Icon(
                          category['icon'] as IconData,
                          color: isSelected ? const Color(0xFF283593) : Colors.black45,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF283593) : Colors.black54,
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
