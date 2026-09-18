import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';

// ─── Modèle local d'une variante ─────────────────────────────────────────────

class _VLocal {
  String color;
  String size;
  bool   available;
  List<XFile>  newImages;
  List<String> existingImages;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;

  _VLocal({
    this.color = '',
    this.size  = '',
    this.available = true,
    List<XFile>?  newImages,
    List<String>? existingImages,
    double price = 0,
    int    stock = 0,
  })  : newImages       = newImages       ?? [],
        existingImages  = existingImages  ?? [],
        priceCtrl = TextEditingController(
            text: price > 0 ? price.toStringAsFixed(0) : ''),
        stockCtrl = TextEditingController(
            text: stock > 0 ? stock.toString() : '');

  String get label =>
      color.isNotEmpty && size.isNotEmpty ? '$color / $size'
          : color.isNotEmpty ? color
          : size;

  double get price => double.tryParse(priceCtrl.text) ?? 0;
  int    get stock => int.tryParse(stockCtrl.text)    ?? 0;

  void dispose() {
    priceCtrl.dispose();
    stockCtrl.dispose();
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? initialProduct;

  const AddProductScreen({this.initialProduct, super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading         = false;
  bool _isFetchingWallets = true;

  // ─── Media généraux (si pas de variantes) ─────────────────────────────────
  final List<XFile> _generalImages = [];
  XFile?   _pickedVideo;
  String?  _existingVideoUrl;
  bool     _removeExistingVideo = false;
  bool     _isPickingVideo      = false;
  final    ImagePicker _picker  = ImagePicker();

  // ─── Controllers ──────────────────────────────────────────────────────────
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _oldPriceCtrl;

  // ─── Variantes ────────────────────────────────────────────────────────────
  bool _hasColors = false;
  bool _hasSizes  = false;

  // Variantes couleurs (chacune indépendante)
  final List<_VLocal> _colorVariants = [];
  // Variantes tailles (chacune indépendante)
  final List<_VLocal> _sizeVariants  = [];
  // Variantes combinées color+size (auto-générées)
  final List<_VLocal> _comboVariants = [];

  final _colorNameCtrl = TextEditingController();
  final _sizeNameCtrl  = TextEditingController();

  // ─── Categories ───────────────────────────────────────────────────────────
  final List<String> _categories = [
    'Maison','Beauté','Électronique','Mode','Livres',
    'Sports','Alimentation','Automobile','Jouets','Jardin',
  ];
  String? _selectedCategory;
  String? _selectedSubCategory;

  // ─── Statut & Pays (NOUVEAU) ────────────────────────────────────────────────
  String? _status;         // 'En stock' | 'Limité'
  String? _sellerCountry;  // Code ISO-2, ex: 'CM'

  static const List<DropdownMenuItem<String>> _countryItems = [
    DropdownMenuItem(value: 'CM', child: Text('🇨🇲 Cameroun (CM)')),
    DropdownMenuItem(value: 'FR', child: Text('🇫🇷 France (FR)')),
    DropdownMenuItem(value: 'CN', child: Text('🇨🇳 Chine (CN)')),
    DropdownMenuItem(value: 'US', child: Text('🇺🇸 États-Unis (US)')),
    DropdownMenuItem(value: 'NG', child: Text('🇳🇬 Nigeria (NG)')),
    DropdownMenuItem(value: 'SN', child: Text('🇸🇳 Sénégal (SN)')),
    DropdownMenuItem(value: 'CI', child: Text('🇨🇮 Côte d\'Ivoire (CI)')),
    DropdownMenuItem(value: 'MA', child: Text('🇲🇦 Maroc (MA)')),
    DropdownMenuItem(value: 'DZ', child: Text('🇩🇿 Algérie (DZ)')),
    DropdownMenuItem(value: 'GH', child: Text('🇬🇭 Ghana (GH)')),
    DropdownMenuItem(value: 'ZA', child: Text('🇿🇦 Afrique du Sud (ZA)')),
    DropdownMenuItem(value: 'GB', child: Text('🇬🇧 Royaume-Uni (GB)')),
    DropdownMenuItem(value: 'DE', child: Text('🇩🇪 Allemagne (DE)')),
    DropdownMenuItem(value: 'TR', child: Text('🇹🇷 Turquie (TR)')),
    DropdownMenuItem(value: 'IN', child: Text('🇮🇳 Inde (IN)')),
    DropdownMenuItem(value: 'JP', child: Text('🇯🇵 Japon (JP)')),
    DropdownMenuItem(value: 'AE', child: Text('🇦🇪 Émirats arabes unis (AE)')),
    DropdownMenuItem(value: 'CD', child: Text('🇨🇩 RD Congo (CD)')),
    DropdownMenuItem(value: 'TG', child: Text('🇹🇬 Togo (TG)')),
    DropdownMenuItem(value: 'GA', child: Text('🇬🇦 Gabon (GA)')),
  ];

  final Map<String, List<String>> _subCategoriesMap = {
    'Mode'         : ['Femme','Homme','Enfants','Accessoires'],
    'Électronique' : ['Électricité','Quincaillerie','Smartphones','Informatique'],
    'Maison'       : ['Mobilier','Meubles','Décoration','Électroménager'],
    'Beauté'       : ['Maquillage','Soins','Parfums','Hygiène'],
    'Livres'       : ['Romans','Scolaire','BD','Dév. Personnel'],
    'Sports'       : ['Fitness','Football','Outdoor','Combat'],
    'Alimentation' : ['Épicerie','Boissons','Frais','Surgelés'],
    'Automobile'   : ['Pièces','Accessoires','Entretien','Pneus'],
    'Jouets'       : ['Jeux de société','Éveil','Consoles','Figurines'],
    'Jardin'       : ['Outils','Plantes','Mobilier de jardin'],
  };

  // ─── Wallets ──────────────────────────────────────────────────────────────
  List<dynamic> _userWallets          = [];
  String?       _selectedWalletAddress;

  bool get _isEditing => widget.initialProduct != null;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  // ─── Palette ──────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _accent     = Color(0xFF00B4D8);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);
  static const Color _green      = Color(0xFF10B981);
  static const Color _red        = Color(0xFFEF4444);

  static const Map<String, IconData> _catIcons = {
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

  // ─── Init ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    final p = widget.initialProduct;
    _nameCtrl        = TextEditingController(text: p?['title']       ?? '');
    _descCtrl        = TextEditingController(text: p?['description'] ?? '');
    _priceCtrl       = TextEditingController(text: p?['price']?.toString()    ?? '');
    _oldPriceCtrl    = TextEditingController(text: p?['oldPrice']?.toString() ?? '');
    _selectedCategory    = p?['category'];
    _selectedSubCategory = p?['subCategory'];
    _selectedWalletAddress = p?['sellerWallet'];
    _existingVideoUrl = p?['video']?.toString();
    _status         = p?['status']?.toString();
    _sellerCountry  = p?['sellerCountry']?.toString();
    if (_sellerCountry != null && _sellerCountry!.isEmpty) _sellerCountry = null;

    if (p != null) {
      _hasColors = p['hasColors'] == true;
      _hasSizes  = p['hasSizes']  == true;

      final variants = p['variants'] as List? ?? [];
      for (final v in variants) {
        final entry = _VLocal(
          color:          v['color']  ?? '',
          size:           v['size']   ?? '',
          existingImages: List<String>.from(v['images'] ?? []),
          price:   (v['price'] as num?)?.toDouble() ?? 0,
          stock:   (v['stock'] as num?)?.toInt()    ?? 0,
          available: v['available'] != false,
        );
        if (_hasColors && _hasSizes) {
          _comboVariants.add(entry);
        } else if (_hasColors) {
          _colorVariants.add(entry);
        } else if (_hasSizes) {
          _sizeVariants.add(entry);
        }
      }
    }

    _fetchMyWallets();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose(); _descCtrl.dispose();
    _priceCtrl.dispose(); _oldPriceCtrl.dispose();
    _colorNameCtrl.dispose(); _sizeNameCtrl.dispose();
    for (final v in _colorVariants) v.dispose();
    for (final v in _sizeVariants)  v.dispose();
    for (final v in _comboVariants) v.dispose();
    super.dispose();
  }

  // ─── Wallets ──────────────────────────────────────────────────────────────
  Future<void> _fetchMyWallets() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) { if (mounted) setState(() => _isFetchingWallets = false); return; }
    setState(() => _isFetchingWallets = true);
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/wallets'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _userWallets = json.decode(res.body);
          if (_userWallets.isNotEmpty && _selectedWalletAddress == null) {
            _selectedWalletAddress = _userWallets.first['address'];
          }
        });
      }
    } catch (e) { debugPrint('Erreur wallets: $e'); }
    finally { if (mounted) setState(() => _isFetchingWallets = false); }
  }

  // ─── Media ────────────────────────────────────────────────────────────────
  Future<void> _pickGeneralImages() async {
    final sel = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1200);
    if (sel.isNotEmpty) setState(() => _generalImages.addAll(sel.take(6 - _generalImages.length)));
  }

  Future<void> _pickVariantImages(_VLocal variant) async {
    final sel = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1200);
    if (sel.isNotEmpty) setState(() => variant.newImages.addAll(sel));
  }

  Future<void> _pickVideo() async {
    setState(() => _isPickingVideo = true);
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
      if (video != null) {
        if (!kIsWeb) {
          final sz = await File(video.path).length();
          if (sz > 100 * 1024 * 1024) {
            _showSnack('Vidéo trop volumineuse (max 100 MB).', Colors.red, Icons.error_outline);
            return;
          }
        }
        setState(() { _pickedVideo = video; _removeExistingVideo = false; });
      }
    } catch (e) { debugPrint('Video error: $e'); }
    finally { if (mounted) setState(() => _isPickingVideo = false); }
  }

  // ─── Génération combos ────────────────────────────────────────────────────
  void _syncComboVariants() {
    if (!_hasColors || !_hasSizes) return;
    final colors = _colorVariants.map((v) => v.color).toList();
    final sizes  = _sizeVariants.map((v) => v.size).toList();

    // Supprimer les combos dont la couleur ou taille n'existe plus
    _comboVariants.removeWhere((c) => !colors.contains(c.color) || !sizes.contains(c.size));

    // Ajouter les combos manquantes
    for (final color in colors) {
      for (final size in sizes) {
        final exists = _comboVariants.any((c) => c.color == color && c.size == size);
        if (!exists) {
          // Récupérer les images de la couleur par défaut
          final colorV = _colorVariants.firstWhere((v) => v.color == color, orElse: () => _VLocal(color: color));
          _comboVariants.add(_VLocal(
            color: color, size: size,
            existingImages: [...colorV.existingImages],
            price: colorV.price,
          ));
        }
      }
    }
    setState(() {});
  }

  // ─── Validation ───────────────────────────────────────────────────────────
  bool _validateVariants() {
    final hasVariants = _hasColors || _hasSizes;
    if (!hasVariants) return true;

    List<_VLocal> toCheck;
    if (_hasColors && _hasSizes) toCheck = _comboVariants;
    else if (_hasColors)         toCheck = _colorVariants;
    else                         toCheck = _sizeVariants;

    if (toCheck.isEmpty) {
      _showSnack('Ajoutez au moins une variante.', Colors.orange, Icons.warning); return false;
    }
    for (final v in toCheck) {
      if (v.label.isEmpty) {
        _showSnack('Renseignez le nom de chaque variante.', Colors.orange, Icons.warning); return false;
      }
      if (v.price <= 0) {
        _showSnack('Prix manquant pour "${v.label}".', Colors.orange, Icons.warning); return false;
      }
      if (v.newImages.isEmpty && v.existingImages.isEmpty) {
        _showSnack('Images manquantes pour "${v.label}".', Colors.orange, Icons.warning); return false;
      }
    }
    return true;
  }

  // ─── Submit ───────────────────────────────────────────────────────────────
  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isApproved) {
      _showSnack('Compte en attente de validation.', const Color(0xFFF59E0B), Icons.warning_amber_rounded); return;
    }
    if (!_validateVariants()) return;
    if (_status == null) {
      _showSnack('Sélectionnez le statut du produit (En stock / Limité).', Colors.orange, Icons.warning);
      return;
    }
    if (_sellerCountry == null || _sellerCountry!.isEmpty) {
      _showSnack('Sélectionnez votre pays.', Colors.orange, Icons.warning);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final productId = _isEditing
          ? (widget.initialProduct!['_id'] ?? widget.initialProduct!['id'])
          : null;
      final url = _isEditing
          ? '${ApiConfig.baseUrl}/products/$productId'
          : '${ApiConfig.baseUrl}/products';

      final request = http.MultipartRequest(_isEditing ? 'PUT' : 'POST', Uri.parse(url));

      // Champs texte
      request.fields['name']        = _nameCtrl.text;
      request.fields['description'] = _descCtrl.text;
      request.fields['price']       = _priceCtrl.text.isEmpty ? '0' : _priceCtrl.text;
      request.fields['oldPrice']    = _oldPriceCtrl.text;
      request.fields['category']    = _selectedCategory    ?? '';
      request.fields['subCategory'] = _selectedSubCategory ?? '';
      request.fields['sellerId']    = auth.currentUser!.id;
      request.fields['sellerName']  = auth.currentUser!.firstName ?? 'Vendeur';
      request.fields['hasColors']   = _hasColors.toString();
      request.fields['hasSizes']    = _hasSizes.toString();
      request.fields['status']        = _status ?? '';
      request.fields['sellerCountry'] = _sellerCountry ?? '';
      if (_selectedWalletAddress != null) request.fields['sellerWallet'] = _selectedWalletAddress!;

      // Construire la liste des variantes à envoyer
      List<_VLocal> allVariants = [];
      if (_hasColors && _hasSizes)  allVariants = _comboVariants;
      else if (_hasColors)          allVariants = _colorVariants;
      else if (_hasSizes)           allVariants = _sizeVariants;

      if (allVariants.isNotEmpty) {
        request.fields['variants'] = json.encode(allVariants.map((v) => {
          'color':          v.color,
          'size':           v.size,
          'price':          v.price,
          'stock':          v.stock,
          'available':      v.available,
          'existingImages': v.existingImages,
        }).toList());

        // Images par variante
        for (int i = 0; i < allVariants.length; i++) {
          for (final xf in allVariants[i].newImages) {
            final bytes = await xf.readAsBytes();
            final ext   = p.extension(xf.name).toLowerCase().replaceAll('.', '');
            request.files.add(http.MultipartFile.fromBytes(
              'variant_images_$i',
              bytes,
              filename:    xf.name,
              contentType: MediaType('image', ext.isEmpty ? 'jpeg' : ext),
            ));
          }
        }
      }

      // Images générales (pas de variantes)
      if (!_hasColors && !_hasSizes) {
        for (final xf in _generalImages) {
          final bytes = await xf.readAsBytes();
          final ext   = p.extension(xf.name).toLowerCase().replaceAll('.', '');
          request.files.add(http.MultipartFile.fromBytes(
            'images', bytes,
            filename:    xf.name,
            contentType: MediaType('image', ext.isEmpty ? 'jpeg' : ext),
          ));
        }
      }

      // Vidéo — contentType explicite pour fix upload
      if (_pickedVideo != null) {
        final bytes = await _pickedVideo!.readAsBytes();
        final ext   = p.extension(_pickedVideo!.name).toLowerCase().replaceAll('.', '');
        final mime  = ['mp4','mov','avi','webm','mkv'].contains(ext) ? ext : 'mp4';
        request.files.add(http.MultipartFile.fromBytes(
          'video', bytes,
          filename:    _pickedVideo!.name,
          contentType: MediaType('video', mime),
        ));
      } else if (_removeExistingVideo) {
        request.fields['removeVideo'] = 'true';
      }

      final response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) context.go('/home');
      } else {
        final body = await response.stream.bytesToString();
        _showSnack('Erreur ${response.statusCode}: $body', Colors.red, Icons.error_outline);
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      _showSnack('Erreur de connexion.', Colors.red, Icons.wifi_off_rounded);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
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
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: _textMain),
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(_isEditing ? 'Modifier le produit' : 'Publier un produit',
            style: const TextStyle(color: _textMain, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _primaryMid.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text('Édition', style: TextStyle(color: _primaryMid, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: _isFetchingWallets
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!auth.isApproved)
                  _Banner(
                    icon: Icons.hourglass_top_rounded,
                    message: "Compte en attente de validation. Vous ne pouvez pas publier pour l'instant.",
                    color: const Color(0xFFF59E0B),
                    bgColor: const Color(0xFFFFFBEB),
                    borderColor: const Color(0xFFFDE68A),
                  ),

                // ── Catégorie ─────────────────────────────────────
                const _SectionLabel(label: 'Classification'),
                const SizedBox(height: 10),
                _buildCategoryCard(currentSubCats),
                const SizedBox(height: 28),

                // ── Statut & Pays (NOUVEAU) ─────────────────────────
                const _SectionLabel(label: 'Disponibilité & Origine'),
                const SizedBox(height: 10),
                _buildAvailabilityCard(),
                const SizedBox(height: 28),

                // ── Infos ─────────────────────────────────────────
                const _SectionLabel(label: 'Informations du produit'),
                const SizedBox(height: 10),
                _buildInfoCard(),
                const SizedBox(height: 28),

                // ── Variantes ─────────────────────────────────────
                const _SectionLabel(label: 'Variantes'),
                const SizedBox(height: 10),
                _buildVariantsSection(),
                const SizedBox(height: 28),

                // ── Médias généraux (si pas de variantes) ─────────
                if (!_hasColors && !_hasSizes) ...[
                  const _SectionLabel(label: 'Photos & Vidéo'),
                  const SizedBox(height: 10),
                  _buildMediaSection(),
                  const SizedBox(height: 28),
                ] else ...[
                  // Vidéo même avec variantes
                  const _SectionLabel(label: 'Vidéo du produit (optionnel)'),
                  const SizedBox(height: 10),
                  _buildVideoSection(),
                  const SizedBox(height: 28),
                ],

                // ── Wallet ────────────────────────────────────────
                if (_userWallets.isNotEmpty) ...[
                  const _SectionLabel(label: 'Portefeuille de paiement'),
                  const SizedBox(height: 10),
                  _buildWalletCard(),
                  const SizedBox(height: 28),
                ],

                // ── Submit ────────────────────────────────────────
                _buildSubmitButton(auth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Section statut & pays (NOUVEAU) ──────────────────────────────────────
  Widget _buildAvailabilityCard() {
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel(label: 'Statut du produit *'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _buildStatusChip(
                label: 'En stock', value: 'En stock',
                color: _green, icon: Icons.check_circle_outline_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatusChip(
                label: 'Limité', value: 'Limité',
                color: _red, icon: Icons.warning_amber_rounded,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          const _FieldLabel(label: 'Pays *'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _sellerCountry,
            decoration: _inputDeco(hint: 'Sélectionner votre pays', icon: Icons.public_rounded),
            items: _countryItems,
            onChanged: (v) => setState(() => _sellerCountry = v),
            validator: (v) => v == null ? 'Requis' : null,
            style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500, fontSize: 14),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final bool selected = _status == value;
    return GestureDetector(
      onTap: () => setState(() => _status = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.10) : _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : _border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? color : _textSub),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13,
              color: selected ? color : _textSub,
            )),
          ],
        ),
      ),
    );
  }

  // ─── Section variantes ────────────────────────────────────────────────────
  Widget _buildVariantsSection() {
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Toggle couleurs ──────────────────────────────────────────
          _buildToggle(
            label:    'Ce produit a plusieurs couleurs',
            sub:      'Chaque couleur aura ses propres images, prix et stock',
            value:    _hasColors,
            onChanged: (v) {
              setState(() {
                _hasColors = v;
                if (!v) { for (final x in _colorVariants) x.dispose(); _colorVariants.clear(); _comboVariants.clear(); }
              });
            },
          ),

          if (_hasColors) ...[
            const SizedBox(height: 16),
            ..._colorVariants.asMap().entries.map((e) => _buildVariantBlock(e.key, e.value, isColor: true)),
            _buildAddVariantRow(
              ctrl:      _colorNameCtrl,
              hint:      'Nom de la couleur (ex: Noir)',
              onAdd:     () {
                final name = _colorNameCtrl.text.trim();
                if (name.isEmpty || _colorVariants.any((v) => v.color == name)) return;
                setState(() {
                  _colorVariants.add(_VLocal(color: name));
                  _colorNameCtrl.clear();
                  if (_hasSizes) _syncComboVariants();
                });
              },
            ),
          ],

          const Divider(height: 28, color: Color(0xFFE2E8F0)),

          // ── Toggle tailles ───────────────────────────────────────────
          _buildToggle(
            label:    'Ce produit a plusieurs tailles',
            sub:      'Chaque taille aura ses propres images, prix et stock',
            value:    _hasSizes,
            onChanged: (v) {
              setState(() {
                _hasSizes = v;
                if (!v) { for (final x in _sizeVariants) x.dispose(); _sizeVariants.clear(); _comboVariants.clear(); }
              });
            },
          ),

          if (_hasSizes) ...[
            const SizedBox(height: 16),
            ..._sizeVariants.asMap().entries.map((e) => _buildVariantBlock(e.key, e.value, isColor: false)),
            _buildAddVariantRow(
              ctrl:      _sizeNameCtrl,
              hint:      'Nom de la taille (ex: S, M, 42...)',
              onAdd:     () {
                final name = _sizeNameCtrl.text.trim();
                if (name.isEmpty || _sizeVariants.any((v) => v.size == name)) return;
                setState(() {
                  _sizeVariants.add(_VLocal(size: name));
                  _sizeNameCtrl.clear();
                  if (_hasColors) _syncComboVariants();
                });
              },
            ),
          ],

          // ── Tableau combos (couleurs + tailles) ──────────────────────
          if (_hasColors && _hasSizes && _comboVariants.isNotEmpty) ...[
            const Divider(height: 28, color: Color(0xFFE2E8F0)),
            const _FieldLabel(label: 'Variantes combinées'),
            const SizedBox(height: 4),
            Text('Définissez prix, stock et images pour chaque combinaison.',
                style: TextStyle(color: _textSub, fontSize: 11)),
            const SizedBox(height: 12),
            ..._comboVariants.asMap().entries.map((e) => _buildComboRow(e.key, e.value)),
          ],
        ],
      ),
    );
  }

  Widget _buildToggle({required String label, required String sub, required bool value, required ValueChanged<bool> onChanged}) {
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _FieldLabel(label: label),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(color: _textSub, fontSize: 11)),
      ])),
      Switch(value: value, activeColor: _primary, onChanged: onChanged),
    ]);
  }

  Widget _buildVariantBlock(int index, _VLocal variant, {required bool isColor}) {
    final list = isColor ? _colorVariants : _sizeVariants;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.06),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(13), topRight: Radius.circular(13)),
            ),
            child: Row(children: [
              Icon(isColor ? Icons.palette_outlined : Icons.straighten_rounded, color: _primary, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(variant.label,
                  style: const TextStyle(color: _primary, fontWeight: FontWeight.w700, fontSize: 14))),
              GestureDetector(
                onTap: () => setState(() {
                  variant.dispose();
                  list.removeAt(index);
                  if (isColor && _hasSizes) _syncComboVariants();
                  if (!isColor && _hasColors) _syncComboVariants();
                }),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.close, color: _red, size: 14),
                ),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Images de cette variante
                const _FieldLabel(label: 'Images de cette variante *'),
                const SizedBox(height: 8),
                _buildVariantImagesPicker(variant),

                const SizedBox(height: 14),

                // Prix + Stock
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _FieldLabel(label: 'Prix *'),
                    const SizedBox(height: 6),
                    _buildSmallField(ctrl: variant.priceCtrl, hint: '0', prefix: '\$ '),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _FieldLabel(label: 'Stock'),
                    const SizedBox(height: 6),
                    _buildSmallField(ctrl: variant.stockCtrl, hint: '0'),
                  ])),
                  const SizedBox(width: 12),
                  // Disponible
                  Column(children: [
                    const _FieldLabel(label: 'Dispo'),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => setState(() => variant.available = !variant.available),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: variant.available ? _green.withOpacity(0.1) : _red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: variant.available ? _green.withOpacity(0.3) : _red.withOpacity(0.3)),
                        ),
                        child: Icon(variant.available ? Icons.check_circle_outline : Icons.block,
                            color: variant.available ? _green : _red, size: 20),
                      ),
                    ),
                  ]),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantImagesPicker(_VLocal variant) {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Bouton ajouter
          GestureDetector(
            onTap: () => _pickVariantImages(variant),
            child: Container(
              width: 76, height: 76,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border, width: 1.5),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_outlined, color: _primary, size: 22),
                const SizedBox(height: 2),
                Text('Photos', style: TextStyle(color: _primary, fontSize: 9, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),

          // Images existantes
          ...variant.existingImages.asMap().entries.map((e) => Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 76, height: 76,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                clipBehavior: Clip.antiAlias,
                child: Image.network(e.value, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: _surface, child: const Icon(Icons.broken_image_outlined, size: 24, color: Colors.grey))),
              ),
              Positioned(
                top: -4, right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => variant.existingImages.removeAt(e.key)),
                  child: Container(width: 18, height: 18,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 11)),
                ),
              ),
            ],
          )),

          // Nouvelles images
          ...variant.newImages.asMap().entries.map((e) => Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 76, height: 76,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                clipBehavior: Clip.antiAlias,
                child: kIsWeb
                    ? Image.network(e.value.path, fit: BoxFit.cover)
                    : Image.file(File(e.value.path), fit: BoxFit.cover),
              ),
              Positioned(
                top: -4, right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => variant.newImages.removeAt(e.key)),
                  child: Container(width: 18, height: 18,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 11)),
                ),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildComboRow(int index, _VLocal combo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: combo.available ? Colors.white : _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: combo.available ? _border : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _primary.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
              child: Text(combo.color, style: TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
              child: Text(combo.size, style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => combo.available = !combo.available),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: combo.available ? _green.withOpacity(0.1) : _red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(combo.available ? Icons.check_circle_outline : Icons.block,
                    color: combo.available ? _green : _red, size: 16),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _buildSmallField(ctrl: combo.priceCtrl, hint: 'Prix', prefix: '\$ ')),
            const SizedBox(width: 10),
            SizedBox(width: 80, child: _buildSmallField(ctrl: combo.stockCtrl, hint: 'Stock')),
          ]),
          const SizedBox(height: 10),
          // Images de la combo
          const _FieldLabel(label: 'Images (optionnel — hérite de la couleur par défaut)'),
          const SizedBox(height: 6),
          _buildVariantImagesPicker(combo),
        ],
      ),
    );
  }

  Widget _buildAddVariantRow({required TextEditingController ctrl, required String hint, required VoidCallback onAdd}) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: ctrl,
          decoration: _inputDeco(hint: hint, icon: Icons.add_circle_outline),
        ),
      ),
      const SizedBox(width: 8),
      ElevatedButton(
        onPressed: onAdd,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: const Text('Ajouter'),
      ),
    ]);
  }

  // ─── Section médias généraux ──────────────────────────────────────────────
  Widget _buildMediaSection() {
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const _FieldLabel(label: 'Images produit (max 6)'),
            Text('${_generalImages.length}/6',
                style: TextStyle(color: _generalImages.length >= 6 ? Colors.orange : _textSub, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),

          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (_generalImages.length < 6)
                  GestureDetector(
                    onTap: _pickGeneralImages,
                    child: Container(
                      width: 96, height: 96,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border, width: 1.5)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_outlined, color: _primary, size: 28),
                        const SizedBox(height: 4),
                        Text('Ajouter', style: TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),

                ..._generalImages.asMap().entries.map((e) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 96, height: 96,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: e.key == 0 ? Border.all(color: _primary, width: 2) : Border.all(color: _border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: kIsWeb ? Image.network(e.value.path, fit: BoxFit.cover) : Image.file(File(e.value.path), fit: BoxFit.cover),
                    ),
                    if (e.key == 0)
                      Positioned(
                        bottom: 4, left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(4)),
                          child: const Text('Principale', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    Positioned(
                      top: -4, right: 6,
                      child: GestureDetector(
                        onTap: () => setState(() => _generalImages.removeAt(e.key)),
                        child: Container(width: 20, height: 20,
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 12)),
                      ),
                    ),
                  ],
                )),

                if (_generalImages.isEmpty && _isEditing && widget.initialProduct?['thumbnail'] != null)
                  Container(
                    width: 96, height: 96,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _primary, width: 2)),
                    clipBehavior: Clip.antiAlias,
                    child: Image.network(widget.initialProduct!['thumbnail'], fit: BoxFit.cover),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          _buildVideoSection(),
        ],
      ),
    );
  }

  // ─── Section vidéo (FIX complet) ──────────────────────────────────────────
  Widget _buildVideoSection() {
    final hasExistingVideo = _existingVideoUrl != null && _existingVideoUrl!.isNotEmpty && !_removeExistingVideo;

    return Container(
      decoration: _hasColors || _hasSizes ? _card() : const BoxDecoration(),
      padding: (_hasColors || _hasSizes) ? const EdgeInsets.all(16) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasColors || _hasSizes)
            const _FieldLabel(label: 'Vidéo du produit (optionnel · max 3 min · 100 MB)'),
          if (_hasColors || _hasSizes) const SizedBox(height: 10),

          // Vidéo existante (mode édition)
          if (hasExistingVideo) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primary.withOpacity(0.15)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.videocam_rounded, color: _primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Vidéo actuelle', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('Votre produit a une vidéo.', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    ]),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _removeExistingVideo = true),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.delete_outline_rounded, color: _red, size: 18),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // Lecteur vidéo HTML natif
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity, height: 160,
                    color: Colors.black,
                    child: kIsWeb
                        ? _VideoWebWidget(url: _existingVideoUrl!)
                        : const Center(child: Icon(Icons.play_circle_fill, color: Colors.white54, size: 48)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isPickingVideo ? null : _pickVideo,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Remplacer la vidéo'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _primary.withOpacity(0.4)),
                  foregroundColor: _primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],

          // Nouvelle vidéo sélectionnée
          if (_pickedVideo != null) ...[
            if (hasExistingVideo) const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withOpacity(0.2)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.check_circle_outline, color: _green, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.basename(_pickedVideo!.name), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 13)),
                    const Text('Prête à être uploadée', style: TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                  ]),
                ),
                GestureDetector(
                  onTap: () => setState(() => _pickedVideo = null),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.delete_outline_rounded, color: _red, size: 18),
                  ),
                ),
              ]),
            ),
          ],

          // Bouton sélectionner (si pas de vidéo)
          if (!hasExistingVideo && _pickedVideo == null)
            GestureDetector(
              onTap: _isPickingVideo ? null : _pickVideo,
              child: Container(
                width: double.infinity, height: 54,
                decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border, width: 1.5)),
                child: _isPickingVideo
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A237E))))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.video_call_outlined, color: _primary, size: 22),
                  const SizedBox(width: 8),
                  Text('Sélectionner une vidéo (max 3 min)', style: TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Category card ────────────────────────────────────────────────────────
  Widget _buildCategoryCard(List<String> currentSubCats) {
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _categories.map((cat) {
            final bool sel = _selectedCategory == cat;
            return GestureDetector(
              onTap: () => setState(() { _selectedCategory = cat; _selectedSubCategory = null; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _primary : _surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? _primary : _border, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_catIcons[cat] ?? Icons.category_outlined, size: 14, color: sel ? Colors.white : _textSub),
                  const SizedBox(width: 6),
                  Text(cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : _textSub)),
                ]),
              ),
            );
          }).toList(),
        ),
        if (_selectedCategory != null && currentSubCats.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          const _FieldLabel(label: 'Sous-catégorie'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedSubCategory,
            decoration: _inputDeco(hint: 'Choisir une sous-catégorie', icon: Icons.subdirectory_arrow_right_rounded),
            items: currentSubCats.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() => _selectedSubCategory = val),
            validator: (v) => v == null ? 'Veuillez choisir une sous-catégorie' : null,
            style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500, fontSize: 14),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ]),
    );
  }

  // ─── Info card ────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _FieldLabel(label: 'Nom du produit *'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameCtrl,
          style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500),
          decoration: _inputDeco(hint: 'Ex: T-Shirt premium coton bio', icon: Icons.label_outline_rounded),
          validator: (v) => v!.isEmpty ? 'Requis' : null,
        ),
        const SizedBox(height: 18),
        const _FieldLabel(label: 'Description'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descCtrl,
          maxLines: 4,
          style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500),
          decoration: _inputDeco(hint: 'Décrivez votre produit...', icon: Icons.notes_rounded),
        ),
        if (!_hasColors && !_hasSizes) ...[
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _FieldLabel(label: 'Prix actuel *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: _textMain, fontWeight: FontWeight.w600),
                decoration: _inputDeco(hint: '0', icon: Icons.sell_outlined, prefixText: '\$ '),
                validator: (v) => v!.isEmpty ? 'Requis' : null,
              ),
            ])),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _FieldLabel(label: 'Ancien prix'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _oldPriceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: _textMain, fontWeight: FontWeight.w500),
                decoration: _inputDeco(hint: '0', icon: Icons.money_off_outlined, prefixText: '\$ '),
              ),
            ])),
          ]),
        ] else ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primary.withOpacity(0.15)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: _primary.withOpacity(0.7), size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text('Le prix est défini dans chaque variante.', style: TextStyle(color: _primary.withOpacity(0.8), fontSize: 11))),
            ]),
          ),
        ],
      ]),
    );
  }

  // ─── Wallet card ──────────────────────────────────────────────────────────
  Widget _buildWalletCard() {
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _FieldLabel(label: 'Adresse du portefeuille'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedWalletAddress,
          decoration: _inputDeco(hint: 'Choisir un portefeuille', icon: Icons.account_balance_wallet_outlined),
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
          Text('Paiements sécurisés via Escrow PLEXUS.', style: TextStyle(fontSize: 11, color: _textSub.withOpacity(0.8))),
        ]),
      ]),
    );
  }

  // ─── Submit ───────────────────────────────────────────────────────────────
  Widget _buildSubmitButton(AuthProvider auth) {
    final bool disabled = _isLoading || !auth.isApproved;
    return SizedBox(
      width: double.infinity, height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: disabled ? null : const LinearGradient(colors: [_primary, _primaryMid], begin: Alignment.centerLeft, end: Alignment.centerRight),
          color: disabled ? _border : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled ? [] : [BoxShadow(color: _primary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: ElevatedButton(
          onPressed: disabled ? null : _submitProduct,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_isEditing ? Icons.save_rounded : Icons.rocket_launch_rounded, color: Colors.white, size: 17),
            const SizedBox(width: 10),
            Text(_isEditing ? 'ENREGISTRER' : "PUBLIER L'ARTICLE",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  BoxDecoration _card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    boxShadow: [BoxShadow(color: _primary.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
  );

  Widget _buildSmallField({required TextEditingController ctrl, required String hint, String? prefix}) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: hint, prefixText: prefix, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primary, width: 1.5)),
        filled: true, fillColor: _surface,
      ),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  InputDecoration _inputDeco({required String hint, required IconData icon, String? prefixText}) {
    return InputDecoration(
      hintText: hint, hintStyle: TextStyle(color: _textSub.withOpacity(0.5), fontSize: 14),
      prefixIcon: Icon(icon, color: _textSub, size: 20),
      prefixText: prefixText,
      filled: true, fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primaryMid, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2)),
    );
  }
}

// ─── Widget vidéo Web (HTML natif) ────────────────────────────────────────────
class _VideoWebWidget extends StatelessWidget {
  final String url;
  const _VideoWebWidget({required this.url});

  @override
  Widget build(BuildContext context) {
    // Sur Flutter Web, on utilise un HtmlElementView ou simplement un lien
    return GestureDetector(
      onTap: () {
        // Ouvre la vidéo dans un nouvel onglet
      },
      child: Container(
        color: Colors.black,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.play_circle_fill, color: Colors.white54, size: 48),
          const SizedBox(height: 8),
          const Text('Appuyez pour voir la vidéo', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 16, decoration: BoxDecoration(color: const Color(0xFF1A237E), borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
  ]);
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)));
}

class _Banner extends StatelessWidget {
  final IconData icon; final String message;
  final Color color, bgColor, borderColor;
  const _Banner({required this.icon, required this.message, required this.color, required this.bgColor, required this.borderColor});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor, width: 1.2)),
    child: Row(children: [
      Icon(icon, color: color, size: 18), const SizedBox(width: 12),
      Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500, height: 1.4))),
    ]),
  );
}