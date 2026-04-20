import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';

enum UserRole { client, seller }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  bool _isGettingLocation = false;
  Set<UserRole> _selectedRole = {UserRole.client};

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _referralController = TextEditingController();

  Uint8List? _idFrontBytes;
  Uint8List? _idBackBytes;
  Uint8List? _selfieBytes;
  
  File? _idFrontFile;
  File? _idBackFile;
  File? _selfieFile;

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  void _showLegalDocs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("📜 Documents Légaux - PLEXUS", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("1. MENTIONS LÉGALES", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("© 2026 PLEXUS GLOBAL SOLUTIONS FZ-LLC.\n"),
              Text("2. CONDITIONS GÉNÉRALES (CGV)", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("- Paiement Escrow sécurisé.\n- Commission de 3% sur les ventes.\n- Livraison responsable du vendeur.\n"),
              Text("3. CONFIDENTIALITÉ", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("PLEXUS ne stocke jamais vos clés privées."),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("FERMER")),
          ElevatedButton(
            onPressed: () { setState(() => _acceptedTerms = true); Navigator.pop(context); },
            child: const Text("J'ACCEPTE"),
          )
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Services désactivés';
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      Position pos = await Geolocator.getCurrentPosition();
      List<Placemark> marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        setState(() {
          _addressController.text = "${marks[0].street}, ${marks[0].locality}, ${marks[0].country}";
        });
      }
    } catch (e) {
      _showError("Localisation impossible");
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _showImagePickerOptions(bool isFront, {bool isSelfie = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF1A237E)),
              title: Text(isSelfie ? "Prendre un selfie" : "Prendre une photo"),
              onTap: () { Navigator.pop(context); _pickImage(isFront, ImageSource.camera, isSelfie: isSelfie); },
            ),
            if (!isSelfie)
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.orange),
                title: const Text("Galerie"),
                onTap: () { Navigator.pop(context); _pickImage(isFront, ImageSource.gallery); },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(bool isFront, ImageSource source, {bool isSelfie = false}) async {
    try {
      final XFile? image = await _picker.pickImage(source: source, preferredCameraDevice: isSelfie ? CameraDevice.front : CameraDevice.rear, imageQuality: 70);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          if (isSelfie) { _selfieBytes = bytes; if (!kIsWeb) _selfieFile = File(image.path); }
          else if (isFront) { _idFrontBytes = bytes; if (!kIsWeb) _idFrontFile = File(image.path); }
          else { _idBackBytes = bytes; if (!kIsWeb) _idBackFile = File(image.path); }
        });
      }
    } catch (e) { debugPrint("Erreur capture: $e"); }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!_acceptedTerms) { _showError("Veuillez accepter les conditions légales"); return; }
    setState(() => _isGoogleLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.signInWithGoogle(referralCode: _referralController.text.trim(), role: 'client');
      if (auth.currentUser != null && mounted) {
        final userId = auth.currentUser!.id;
        final notifP = Provider.of<NotificationProvider>(context, listen: false);
        Provider.of<SocketProvider>(context, listen: false).connect(userId, notifP);
        notifP.fetchNotifications(userId);
      }
    } catch (e) { _showError("Erreur Google"); }
    finally { if (mounted) setState(() => _isGoogleLoading = false); }
  }

  void _showError(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.black87, behavior: SnackBarBehavior.floating));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) { _showError("Vous devez accepter les conditions légales"); return; }
    if (_selectedRole.first == UserRole.seller) {
      if (_idFrontBytes == null || _idBackBytes == null || _selfieBytes == null) { _showError("Dossier KYC incomplet"); return; }
    }
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.signUp(_nameController.text, _emailController.text, _passwordController.text, _selectedRole.first.name, phone: _phoneController.text, address: _addressController.text, idFront: _idFrontFile, idBack: _idBackFile, selfie: _selfieFile, referralCode: _referralController.text.trim());
      if (mounted && auth.pendingEmail != null) context.go('/verify');
    } catch (e) { _showError(e.toString()); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);
    bool isSeller = _selectedRole.first == UserRole.seller;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- HEADER PREMIUM ---
            Container(
              height: 220, width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [primaryColor, Color(0xFF3949AB)]),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(100)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Hero(tag: 'logo', child: Image.asset('assets/logo/logo.png', height: 70, errorBuilder: (c,e,s) => const Icon(Icons.person_add_rounded, size: 50, color: Colors.white))),
                  const SizedBox(height: 10),
                  const Text('INSCRIPTION', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(30.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    SegmentedButton<UserRole>(
                      segments: const [
                        ButtonSegment(value: UserRole.client, label: Text('CLIENT'), icon: Icon(Icons.shopping_bag_outlined)),
                        ButtonSegment(value: UserRole.seller, label: Text('VENDEUR'), icon: Icon(Icons.storefront_rounded)),
                      ],
                      selected: _selectedRole,
                      onSelectionChanged: (v) => setState(() => _selectedRole = v),
                    ),
                    const SizedBox(height: 30),
                    
                    if (!isSeller) ...[
                      SizedBox(
                        width: double.infinity, height: 60,
                        child: OutlinedButton(
                          onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
                          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), side: BorderSide(color: Colors.grey[200]!, width: 2)),
                          child: _isGoogleLoading ? const CircularProgressIndicator() : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.network('https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg', width: 20),
                              const SizedBox(width: 10),
                              const Text("Continuer avec Google", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Text("OU", style: TextStyle(color: Colors.grey, fontSize: 10))),
                    ],

                    _buildField(_nameController, 'Nom complet', Icons.person_outline_rounded),
                    const SizedBox(height: 15),
                    _buildField(_emailController, 'Email', Icons.email_outlined),
                    const SizedBox(height: 15),
                    
                    if (isSeller) ...[
                      _buildField(_phoneController, 'Téléphone', Icons.phone_android_rounded),
                      const SizedBox(height: 15),
                      Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          _buildField(_addressController, 'Localisation Boutique', Icons.location_on_outlined),
                          IconButton(icon: Icon(_isGettingLocation ? Icons.hourglass_empty : Icons.my_location, color: primaryColor), onPressed: _getCurrentLocation),
                        ],
                      ),
                      const SizedBox(height: 30),
                      const Text('DOCUMENTS REQUIS', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 11, letterSpacing: 1.5)),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: _buildUploadBox("SELFIE", _selfieBytes, () => _showImagePickerOptions(false, isSelfie: true))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildUploadBox("RECTO", _idFrontBytes, () => _showImagePickerOptions(true))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildUploadBox("VERSO", _idBackBytes, () => _showImagePickerOptions(false))),
                        ],
                      ),
                      const SizedBox(height: 25),
                    ],

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe', prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildField(_referralController, 'Code parrainage (Optionnel)', Icons.card_giftcard_rounded),
                    
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Checkbox(value: _acceptedTerms, onChanged: (v) => setState(() => _acceptedTerms = v!)),
                        Expanded(child: GestureDetector(onTap: _showLegalDocs, child: const Text("J'accepte les conditions légales et la politique de confidentialité", style: TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline), softWrap: true))),
                      ],
                    ),

                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity, height: 60,
                      child: Container(
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]),
                        child: ElevatedButton(
                          onPressed: (_isLoading || !_acceptedTerms) ? null : _submit,
                          style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
                          child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('CRÉER MON COMPTE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(child: TextButton(onPressed: () => context.go('/login'), child: const Text("Déjà un compte ? Se connecter"))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController c, String l, IconData i) {
    return TextFormField(controller: c, decoration: InputDecoration(labelText: l, prefixIcon: Icon(i)), validator: (v) => v!.isEmpty ? 'Requis' : null);
  }

  Widget _buildUploadBox(String label, Uint8List? bytes, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 90,
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)),
        child: bytes == null 
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_a_photo_outlined, size: 24, color: Colors.grey), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey))])
          : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.memory(bytes, fit: BoxFit.cover)),
      ),
    );
  }
}
