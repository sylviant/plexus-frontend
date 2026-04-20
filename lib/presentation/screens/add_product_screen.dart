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

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isFetchingWallets = true;
  File? _image;
  XFile? _pickedFile;
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _oldPriceController;

  final List<String> _categories = [
    'Maison', 'Beauté', 'Électronique', 'Mode', 'Livres', 
    'Sports', 'Alimentation', 'Automobile', 'Jouets', 'Jardin'
  ];
  
  String? _selectedCategory;
  String? _selectedSubCategory; // NOUVEAU

  // Mapping des sous-catégories pour le formulaire
  final Map<String, List<String>> _subCategoriesMap = {
    'Mode': ['Femme', 'Homme', 'Enfants', 'Accessoires'],
    'Électronique': ['Électricité', 'Quincaillerie', 'Smartphones', 'Informatique'],
    'Maison': ['Mobilier', 'Meubles', 'Décoration', 'Électroménager'],
    'Beauté': ['Maquillage', 'Soins', 'Parfums', 'Hygiène'],
    'Livres': ['Romans', 'Scolaire', 'BD', 'Dév. Personnel'],
    'Sports': ['Fitness', 'Football', 'Outdoor', 'Combat'],
    'Alimentation': ['Épicerie', 'Boissons', 'Frais', 'Surgelés'],
    'Automobile': ['Pièces', 'Accessoires', 'Entretien', 'Pneus'],
    'Jouets': ['Jeux de société', 'Éveil', 'Consoles', 'Figurines'],
    'Jardin': ['Outils', 'Plantes', 'Mobilier de jardin'],
  };
  
  List<dynamic> _userWallets = [];
  String? _selectedWalletAddress;

  bool get _isEditing => widget.initialProduct != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProduct?['title'] ?? '');
    _descriptionController = TextEditingController(text: widget.initialProduct?['description'] ?? '');
    _priceController = TextEditingController(text: widget.initialProduct?['price']?.toString() ?? '');
    _oldPriceController = TextEditingController(text: widget.initialProduct?['oldPrice']?.toString() ?? '');
    _selectedCategory = widget.initialProduct?['category'];
    _selectedSubCategory = widget.initialProduct?['subCategory'];
    _selectedWalletAddress = widget.initialProduct?['sellerWallet'];
    _fetchMyWallets();
  }

  Future<void> _fetchMyWallets() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;
    
    setState(() => _isFetchingWallets = true);
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/users/${user.id}/wallets'));
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

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _oldPriceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? selected = await _picker.pickImage(source: ImageSource.gallery);
    if (selected != null) {
      setState(() {
        _pickedFile = selected;
        if (!kIsWeb) _image = File(selected.path);
      });
    }
  }

  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    
    final auth = Provider.of<AuthProvider>(context, listen: false);
    
    if (!auth.isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Votre compte est en attente de validation par PLEXUS.'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_userWallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action impossible : Enregistrez un portefeuille dans votre profil.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final productId = _isEditing ? (widget.initialProduct!['_id'] ?? widget.initialProduct!['id']) : null;
      final String url = _isEditing ? '${ApiConfig.baseUrl}/products/$productId' : '${ApiConfig.baseUrl}/products';
      
      var request = http.MultipartRequest(_isEditing ? 'PUT' : 'POST', Uri.parse(url));

      request.fields['name'] = _nameController.text;
      request.fields['description'] = _descriptionController.text;
      request.fields['price'] = _priceController.text;
      request.fields['oldPrice'] = _oldPriceController.text;
      request.fields['category'] = _selectedCategory ?? '';
      request.fields['subCategory'] = _selectedSubCategory ?? ''; // ENVOI DE LA SOUS-CATÉGORIE
      request.fields['sellerId'] = auth.currentUser!.id;
      request.fields['sellerName'] = auth.currentUser!.firstName ?? 'Vendeur';
      request.fields['sellerWallet'] = _selectedWalletAddress!; 

      if (_pickedFile != null) {
        if (kIsWeb) {
          var bytes = await _pickedFile!.readAsBytes();
          request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: _pickedFile!.name));
        } else {
          request.files.add(await http.MultipartFile.fromPath('image', _image!.path, filename: p.basename(_image!.path)));
        }
      }

      var response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) context.go('/home');
      }
    } catch (e) {
      debugPrint("Erreur: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final List<String> currentSubCats = _selectedCategory != null ? (_subCategoriesMap[_selectedCategory] ?? []) : [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(_isEditing ? "Modifier le produit" : "Publier un produit"), elevation: 0),
      body: _isFetchingWallets 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!auth.isApproved)
                Container(
                  padding: const EdgeInsets.all(15),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange[100]!)),
                  child: const Text("Compte en attente de validation Admin.", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ),

              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 180, width: double.infinity,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                  child: _pickedFile != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(15), child: kIsWeb ? Image.network(_pickedFile!.path, fit: BoxFit.cover) : Image.file(File(_pickedFile!.path), fit: BoxFit.cover))
                      : (_isEditing && widget.initialProduct?['thumbnail'] != null)
                          ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(widget.initialProduct!['thumbnail'], fit: BoxFit.cover))
                          : const Icon(Icons.add_a_photo, size: 50, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),

              // CHOIX CATÉGORIE
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Catégorie principale', border: OutlineInputBorder()),
                value: _selectedCategory,
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCategory = val;
                    _selectedSubCategory = null; // Reset de la sous-catégorie
                  });
                },
                validator: (v) => v == null ? 'Requis' : null,
              ),
              const SizedBox(height: 16),

              // CHOIX SOUS-CATÉGORIE (Dynamique)
              if (_selectedCategory != null)
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Sous-catégorie', border: OutlineInputBorder()),
                  value: _selectedSubCategory,
                  items: currentSubCats.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => setState(() => _selectedSubCategory = val),
                  validator: (v) => v == null ? 'Veuillez choisir une sous-catégorie' : null,
                ),
              const SizedBox(height: 16),

              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nom du produit', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Requis' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()), maxLines: 3),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _priceController, decoration: const InputDecoration(labelText: 'Prix actuel', border: OutlineInputBorder(), prefixText: r'$'), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'Requis' : null)),
                  const SizedBox(width: 10),
                  Expanded(child: TextFormField(controller: _oldPriceController, decoration: const InputDecoration(labelText: 'Ancien prix', border: OutlineInputBorder(), prefixText: r'$'), keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: (_isLoading || _userWallets.isEmpty || !auth.isApproved) ? null : _submitProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF283593),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Publier l'article"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
