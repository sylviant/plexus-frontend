import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? initialProduct;
  const AddProductScreen({this.initialProduct, super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading       = false;
  bool _isFetchingWallets = true;

  // ─── Media state (NOUVEAU : multi-images + vidéo) ───────────────────────────
  final List<XFile> _pickedImages = [];   // plusieurs images
  XFile?            _pickedVideo;         // une vidéo optionnelle
  bool              _isPickingVideo = false;

  final ImagePicker _picker = ImagePicker();

  // ─── Controllers ─────────────────────────────────────────────────────────────
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _oldPriceController;

  // ─── Category data ───────────────────────────────────────────────────────────
  final List<String> _categories = [
    'Maison', 'Beauté', 'Électronique', 'Mode', 'Livres',
    'Sports', 'Alimentation', 'Automobile', 'Jouets', 'Jardin'
  ];
  String? _selectedCategory;
  String? _selectedSubCategory;

  final Map<String, List<String>> _subCategoriesMap = {
    'Mode'         : ['Femme', 'Homme', 'Enfants', 'Accessoires'],
    'Électronique' : ['Électricité', 'Quincaillerie', 'Smartphones', 'Informatique'],
    'Maison'       : ['Mobilier', 'Meubles', 'Décoration', 'Électroménager'],
    'Beauté'       : ['Maquillage', 'Soins', 'Parfums', 'Hygiène'],
    'Livres'       : ['Romans', 'Scolaire', 'BD', 'Dév. Personnel'],
    'Sports'       : ['Fitness', 'Football', 'Outdoor', 'Combat'],
    'Alimentation' : ['Épicerie', 'Boissons', 'Frais', 'Surgelés'],
    'Automobile'   : ['Pièces', 'Accessoires', 'Entretien', 'Pneus'],
    'Jouets'       : ['Jeux de société', 'Éveil', 'Consoles', 'Figurines'],
    'Jardin'       : ['Outils', 'Plantes', 'Mobilier de jardin'],
  };

  // ─── Wallets ─────────────────────────────────────────────────────────────────
  List<dynamic> _userWallets        = [];
  String?       _selectedWalletAddress;

  bool get _isEditing => widget.initialProduct != null;

  late AnimationController _animController;
  late Animation<double>   _fadeAnim;

  // ─── Palette (thème original conservé) ──────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _accent     = Color(0xFF00B4D8);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);

  static const Map<String, IconData> _categoryIcons = {
    'Maison'       : Icons.home_outlined,
    'Beauté'       : Icons.spa_outlined,
    'Électronique' : Icons.devices_outlined,
    'Mode'         : Icons.checkroom_outlined,
    'Livres'       : Icons.menu_book_outlined,
    'Sports'       : Icons.sports_soccer_outlined,
    'Alimentation' : Icons.restaurant_outlined,
    'Automobile'   : Icons.directions_car_outlined,
    'Jouets'       : Icons.toys_outlined,
    'Jardin'       : Icons.yard_outlined,
  };

  // ─── Init ────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _nameController        = TextEditingController(text: widget.initialProduct?['title'] ?? '');
    _descriptionController = TextEditingController(text: widget.initialProduct?['description'] ?? '');
    _priceController       = TextEditingController(text: widget.initialProduct?['price']?.toString() ?? '');
    _oldPriceController    = TextEditingController(text: widget.initialProduct?['oldPrice']?.toString() ?? '');
    _selectedCategory      = widget.initialProduct?['category'];
    _selectedSubCategory   = widget.initialProduct?['subCategory'];
    _selectedWalletAddress = widget.initialProduct?['sellerWallet'];
    _fetchMyWallets();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _oldPriceController.dispose();
    super.dispose();
  }

  // ─── Wallets fetch ───────────────────────────────────────────────────────────
  Future<void> _fetchMyWallets() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;
    setState(() => _isFetchingWallets = true);
    try {
      final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/wallets'));
      if (response.statusCode == 200) {
        setState(() {
          _userWallets = json.decode(response.body);
          if (_userWallets.isNotEmpty && _selectedWalletAddress == null) {
            _selectedWalletAddress = _userWallets.first['address'];
          }
        });
      }
    } catch (e) {
      debugPrint("Erreur wallets: $e");
    } finally {
      setState(() => _isFetchingWallets = false);
    }
  }

  // ─── NOUVEAU : Sélection multiple d'images ───────────────────────────────────
  Future<void> _pickImages() async {
    try {
      // pickMultiImage retourne une List<XFile>
      final List<XFile> selected = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (selected.isNotEmpty) {
        setState(() {
          // On limite à 6 images max
          final remaining = 6 - _pickedImages.length;
          _pickedImages.addAll(selected.take(remaining));
        });
        if (selected.length > (6 - _pickedImages.length + selected.length)) {
          _showSnack('Maximum 6 images autorisées.', _accent, Icons.info_outline);
        }
      }
    } catch (e) {
      debugPrint("Erreur sélection images: $e");
    }
  }

  // ─── NOUVEAU : Sélection d'une vidéo ────────────────────────────────────────
  Future<void> _pickVideo() async {
    setState(() => _isPickingVideo = true);
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2), // limite 2 min
      );
      if (video != null) {
        // Vérification taille (max 50 MB)
        final file = File(video.path);
        final sizeInMB = await file.length() / (1024 * 1024);
        if (sizeInMB > 50) {
          _showSnack('Vidéo trop volumineuse (max 50 MB).', Colors.red, Icons.error_outline);
          return;
        }
        setState(() => _pickedVideo = video);
      }
    } catch (e) {
      debugPrint("Erreur sélection vidéo: $e");
    } finally {
      setState(() => _isPickingVideo = false);
    }
  }

  void _removeImage(int index) {
    setState(() => _pickedImages.removeAt(index));
  }

  void _removeVideo() {
    setState(() => _pickedVideo = null);
  }

  // ─── Submit (MODIFIÉ : envoie images[] + video) ──────────────────────────────
  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (!auth.isApproved) {
      _showSnack('Votre compte est en attente de validation par PLEXUS.',
          const Color(0xFFF59E0B), Icons.warning_amber_rounded);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final productId = _isEditing
          ? (widget.initialProduct!['_id'] ?? widget.initialProduct!['id'])
          : null;
      final String url = _isEditing
          ? '${ApiConfig.baseUrl}/products/$productId'
          : '${ApiConfig.baseUrl}/products';

      final request = http.MultipartRequest(
          _isEditing ? 'PUT' : 'POST', Uri.parse(url));

      // ── Champs texte (inchangés) ────────────────────────────────────────────
      request.fields['name']        = _nameController.text;
      request.fields['description'] = _descriptionController.text;
      request.fields['price']       = _priceController.text;
      request.fields['oldPrice']    = _oldPriceController.text;
      request.fields['category']    = _selectedCategory ?? '';
      request.fields['subCategory'] = _selectedSubCategory ?? '';
      request.fields['sellerId']    = auth.currentUser!.id;
      request.fields['sellerName']  = auth.currentUser!.firstName ?? 'Vendeur';
      if (_selectedWalletAddress != null) {
        request.fields['sellerWallet'] = _selectedWalletAddress!;
      }

      // ── NOUVEAU : Envoi des images (field name: 'images') ───────────────────
      for (final xfile in _pickedImages) {
        if (kIsWeb) {
          final bytes = await xfile.readAsBytes();
          request.files.add(http.MultipartFile.fromBytes(
            'images',          // ← field name attendu par le backend
            bytes,
            filename: xfile.name,
          ));
        } else {
          request.files.add(await http.MultipartFile.fromPath(
            'images',          // ← field name attendu par le backend
            xfile.path,
            filename: p.basename(xfile.path),
          ));
        }
      }

      // ── NOUVEAU : Envoi de la vidéo (field name: 'video') ──────────────────
      if (_pickedVideo != null) {
        if (kIsWeb) {
          final bytes = await _pickedVideo!.readAsBytes();
          request.files.add(http.MultipartFile.fromBytes(
            'video',           // ← field name attendu par le backend
            bytes,
            filename: _pickedVideo!.name,
          ));
        } else {
          request.files.add(await http.MultipartFile.fromPath(
            'video',           // ← field name attendu par le backend
            _pickedVideo!.path,
            filename: p.basename(_pickedVideo!.path),
          ));
        }
      }

      final response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) context.go('/home');
      } else {
        _showSnack('Erreur serveur (${response.statusCode})', Colors.red, Icons.error_outline);
      }
    } catch (e) {
      debugPrint("Erreur: $e");
      _showSnack('Erreur de connexion', Colors.red, Icons.wifi_off_rounded);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final List<String> currentSubCats = _selectedCategory != null
        ? (_subCategoriesMap[_selectedCategory] ?? [])
        : [];

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
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: _textMain),
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _isEditing ? 'Modifier le produit' : 'Publier un produit',
          style: const TextStyle(color: _textMain, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _primaryMid.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Édition',
                    style: TextStyle(color: _primaryMid, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: _isFetchingWallets
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: _primary),
                const SizedBox(height: 16),
                Text('Chargement des portefeuilles...',
                    style: TextStyle(color: _textSub, fontSize: 13)),
              ]),
            )
          : FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Pending approval banner ──────────────────────────────
                      if (!auth.isApproved)
                        _Banner(
                          icon: Icons.hourglass_top_rounded,
                          message: 'Votre compte est en attente de validation par PLEXUS. Vous ne pouvez pas publier pour l\'instant.',
                          color: const Color(0xFFF59E0B),
                          bgColor: const Color(0xFFFFFBEB),
                          borderColor: const Color(0xFFFDE68A),
                        ),

                      // ── MODIFIÉ : Section Médias ─────────────────────────────
                      const _SectionLabel(label: 'Photos & Vidéo du produit'),
                      const SizedBox(height: 10),
                      _buildMediaSection(),

                      const SizedBox(height: 28),

                      // ── Categories (identique) ───────────────────────────────
                      const _SectionLabel(label: 'Classification'),
                      const SizedBox(height: 10),
                      _buildCategoryCard(currentSubCats),

                      const SizedBox(height: 28),

                      // ── Product info (identique) ─────────────────────────────
                      const _SectionLabel(label: 'Informations du produit'),
                      const SizedBox(height: 10),
                      _buildInfoCard(),

                      const SizedBox(height: 28),

                      // ── Wallet selector (identique) ──────────────────────────
                      if (_userWallets.isNotEmpty) ...[
                        const _SectionLabel(label: 'Portefeuille de paiement'),
                        const SizedBox(height: 10),
                        _buildWalletCard(),
                        const SizedBox(height: 28),
                      ],

                      // ── Submit button (identique) ────────────────────────────
                      _buildSubmitButton(auth),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ─── NOUVEAU : Section médias (grille images + bouton vidéo) ─────────────────
  Widget _buildMediaSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _primary.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Compteur ────────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _FieldLabel(label: 'Images (max 6)'),
              Text('${_pickedImages.length}/6',
                  style: TextStyle(
                      color: _pickedImages.length >= 6 ? Colors.orange : _textSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),

          // ── Grille images ────────────────────────────────────────────────────
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Bouton ajouter (désactivé si 6 images atteintes)
                if (_pickedImages.length < 6)
                  GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      width: 96,
                      height: 96,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border, width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, color: _primary, size: 28),
                          const SizedBox(height: 4),
                          Text('Ajouter', style: TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),

                // Images sélectionnées
                ..._pickedImages.asMap().entries.map((entry) {
                  final i    = entry.key;
                  final file = entry.value;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: i == 0
                              ? Border.all(color: _primary, width: 2)
                              : Border.all(color: _border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: kIsWeb
                            ? Image.network(file.path, fit: BoxFit.cover)
                            : Image.file(File(file.path), fit: BoxFit.cover),
                      ),
                      // Badge "Principale" sur la 1ère image
                      if (i == 0)
                        Positioned(
                          bottom: 4, left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Principale',
                                style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      // Bouton supprimer
                      Positioned(
                        top: -4, right: 6,
                        child: GestureDetector(
                          onTap: () => _removeImage(i),
                          child: Container(
                            width: 20, height: 20,
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                    ],
                  );
                }),

                // Placeholder si aucune image
                if (_pickedImages.isEmpty && _isEditing && widget.initialProduct?['thumbnail'] != null)
                  Container(
                    width: 96, height: 96,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _primary, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.network(widget.initialProduct!['thumbnail'], fit: BoxFit.cover),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          // ── Section vidéo ────────────────────────────────────────────────────
          const _FieldLabel(label: 'Vidéo du produit (optionnel · max 2 min · 50 MB)'),
          const SizedBox(height: 10),

          if (_pickedVideo == null)
            GestureDetector(
              onTap: _isPickingVideo ? null : _pickVideo,
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border, width: 1.5),
                ),
                child: _isPickingVideo
                    ? const Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A237E))))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.video_call_outlined, color: _primary, size: 22),
                          const SizedBox(width: 8),
                          Text('Sélectionner une vidéo',
                              style: TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
              ),
            )
          else
            // Aperçu vidéo sélectionnée
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.videocam_rounded, color: _primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.basename(_pickedVideo!.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        Text('Vidéo sélectionnée',
                            style: TextStyle(color: _textSub, fontSize: 11)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _removeVideo,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red, size: 18),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 12, color: _textSub.withOpacity(0.6)),
            const SizedBox(width: 5),
            Text('La première image sera utilisée comme miniature principale.',
                style: TextStyle(fontSize: 10, color: _textSub.withOpacity(0.7))),
          ]),
        ],
      ),
    );
  }

  // ─── Category card (identique à l'original) ───────────────────────────────────
  Widget _buildCategoryCard(List<String> currentSubCats) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _primary.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _categories.map((cat) {
              final bool selected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () => setState(() { _selectedCategory = cat; _selectedSubCategory = null; }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _primary : _surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? _primary : _border, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_categoryIcons[cat] ?? Icons.category_outlined,
                          size: 14, color: selected ? Colors.white : _textSub),
                      const SizedBox(width: 6),
                      Text(cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : _textSub)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_selectedCategory != null && currentSubCats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: _border),
            const SizedBox(height: 12),
            const _FieldLabel(label: 'Sous-catégorie'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedSubCategory,
              decoration: _inputDecoration(hint: 'Choisir une sous-catégorie', icon: Icons.subdirectory_arrow_right_rounded),
              items: currentSubCats.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => setState(() => _selectedSubCategory = val),
              validator: (v) => v == null ? 'Veuillez choisir une sous-catégorie' : null,
              style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500, fontSize: 14),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ],
          if (_selectedCategory == null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.info_outline_rounded, size: 13, color: _textSub.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text('Sélectionnez une catégorie principale',
                  style: TextStyle(fontSize: 11, color: _textSub.withOpacity(0.7))),
            ]),
          ],
        ],
      ),
    );
  }

  // ─── Info card (identique à l'original) ──────────────────────────────────────
  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _primary.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel(label: 'Nom du produit'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500),
            decoration: _inputDecoration(hint: 'Ex: Robe en soie noire taille M', icon: Icons.label_outline_rounded),
            validator: (v) => v!.isEmpty ? 'Requis' : null,
          ),
          const SizedBox(height: 18),
          const _FieldLabel(label: 'Description'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descriptionController,
            maxLines: 4,
            style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500),
            decoration: _inputDecoration(hint: 'Décrivez votre produit : matière, taille, état...', icon: Icons.notes_rounded),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel(label: 'Prix actuel'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: _textMain, fontWeight: FontWeight.w600),
                  decoration: _inputDecoration(hint: '0', icon: Icons.sell_outlined,
                      prefixText: '\$ ', prefixStyle: const TextStyle(color: _primary, fontWeight: FontWeight.w700, fontSize: 14)),
                  validator: (v) => v!.isEmpty ? 'Requis' : null,
                ),
              ],
            )),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel(label: 'Ancien prix'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _oldPriceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500),
                  decoration: _inputDecoration(hint: '0', icon: Icons.money_off_outlined,
                      prefixText: '\$ ', prefixStyle: TextStyle(color: _textSub, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ],
            )),
          ]),
        ],
      ),
    );
  }

  // ─── Wallet card (identique à l'original) ────────────────────────────────────
  Widget _buildWalletCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _primary.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel(label: 'Adresse du portefeuille'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedWalletAddress,
            decoration: _inputDecoration(hint: 'Choisir un portefeuille', icon: Icons.account_balance_wallet_outlined),
            items: _userWallets.map((w) => DropdownMenuItem<String>(
              value: w['address'],
              child: Text(
                '${w['address'].toString().substring(0, 8)}...${w['address'].toString().substring(w['address'].toString().length - 6)}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: _textMain),
              ),
            )).toList(),
            onChanged: (val) => setState(() => _selectedWalletAddress = val),
            style: const TextStyle(color: _textMain, fontSize: 14),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.shield_outlined, size: 13, color: _accent.withOpacity(0.8)),
            const SizedBox(width: 6),
            Text('Les paiements sont sécurisés via Escrow PLEXUS.',
                style: TextStyle(fontSize: 11, color: _textSub.withOpacity(0.8))),
          ]),
        ],
      ),
    );
  }

  // ─── Submit button (identique à l'original) ───────────────────────────────────
  Widget _buildSubmitButton(AuthProvider auth) {
    final bool disabled = _isLoading || !auth.isApproved;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: disabled ? null : const LinearGradient(
              colors: [_primary, _primaryMid],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
          color: disabled ? _border : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled ? [] : [BoxShadow(color: _primary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: ElevatedButton(
          onPressed: disabled ? null : _submitProduct,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _isLoading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isEditing ? Icons.save_rounded : Icons.rocket_launch_rounded,
                        color: Colors.white, size: 17),
                    const SizedBox(width: 10),
                    Text(
                      _isEditing ? 'ENREGISTRER LES MODIFICATIONS' : 'PUBLIER L\'ARTICLE',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                          letterSpacing: 1.2, fontSize: 14),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ─── Input decoration helper ──────────────────────────────────────────────────
  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    String? prefixText,
    TextStyle? prefixStyle,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textSub.withOpacity(0.5), fontSize: 14),
      prefixIcon: Icon(icon, color: _textSub, size: 20),
      prefixText: prefixText,
      prefixStyle: prefixStyle,
      suffixIcon: suffix,
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryMid, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2)),
    );
  }
}

// ─── Sub-widgets (identiques à l'original) ────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 3, height: 16,
          decoration: BoxDecoration(color: const Color(0xFF1A237E), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A), letterSpacing: 0.1)),
    ]);
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: Color(0xFF64748B), letterSpacing: 0.2));
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  const _Banner({required this.icon, required this.message, required this.color,
      required this.bgColor, required this.borderColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2)),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 12,
            fontWeight: FontWeight.w500, height: 1.4))),
      ]),
    );
  }
}