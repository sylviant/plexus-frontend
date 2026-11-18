import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:plexus/l10n/l10n.dart';

enum UserRole { client, seller }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
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

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ─── Palette ────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _accent     = Color(0xFF00B4D8);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  // ─── Backend logic ───────────────────────────────────────────────────────

  void _showLegalDocs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.documentsLegauxPlexus,
          style: TextStyle(
              fontWeight: FontWeight.w800, color: _primary, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.t1MentionsLegales,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              SizedBox(height: 4),
              Text(l10n.t2026PlexusGlobalSolutionsFz,
                  style: TextStyle(fontSize: 13)),
              Text(l10n.t2ConditionsGeneralesCgv,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              SizedBox(height: 4),
              Text(
                  l10n.paiementEscrowSecuriseCommissionDe,
                  style: TextStyle(fontSize: 13)),
              Text(l10n.t3Confidentialite,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              SizedBox(height: 4),
              Text(l10n.plexusNeStockeJamaisVos,
                  style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("FERMER", style: TextStyle(color: _textSub)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _acceptedTerms = true);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l10n.jAccepte,
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw l10n.servicesDesactives;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      Position pos = await Geolocator.getCurrentPosition();
      List<Placemark> marks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        setState(() {
          _addressController.text =
              "${marks[0].street}, ${marks[0].locality}, ${marks[0].country}";
        });
      }
    } catch (e) {
      _showError(l10n.localisationImpossible);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _showImagePickerOptions(bool isFront, {bool isSelfie = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  isSelfie ? l10n.prendreUnSelfie : l10n.ajouterUnDocument,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: _textMain),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: _primary, size: 20),
                ),
                title: Text(
                    isSelfie ? l10n.prendreUnSelfie : l10n.prendreUnePhoto,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(isFront, ImageSource.camera, isSelfie: isSelfie);
                },
              ),
              if (!isSelfie)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_library_rounded,
                        color: Colors.orange, size: 20),
                  ),
                  title: Text(l10n.choisirDepuisLaGalerie,
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(isFront, ImageSource.gallery);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(bool isFront, ImageSource source,
      {bool isSelfie = false}) async {
    try {
      final XFile? image = await _picker.pickImage(
          source: source,
          preferredCameraDevice:
              isSelfie ? CameraDevice.front : CameraDevice.rear,
          imageQuality: 70);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          if (isSelfie) {
            _selfieBytes = bytes;
            if (!kIsWeb) _selfieFile = File(image.path);
          } else if (isFront) {
            _idFrontBytes = bytes;
            if (!kIsWeb) _idFrontFile = File(image.path);
          } else {
            _idBackBytes = bytes;
            if (!kIsWeb) _idBackFile = File(image.path);
          }
        });
      }
    } catch (e) {
      debugPrint("Erreur capture: $e");
    }
  }

  // ✅ Inchangé — délègue au AuthProvider qui gère Web/Mobile
  Future<void> _handleGoogleSignIn() async {
    if (!_acceptedTerms) {
      _showError(l10n.veuillezAccepterLesConditionsLegales);
      return;
    }
    setState(() => _isGoogleLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.signInWithGoogle(
          referralCode: _referralController.text.trim(), role: 'client');
      if (auth.currentUser != null && mounted) {
        final userId = auth.currentUser!.id;
        final notifP =
            Provider.of<NotificationProvider>(context, listen: false);
        Provider.of<SocketProvider>(context, listen: false)
            .connect(userId, notifP);
        notifP.fetchNotifications(userId);
      }
    } catch (e) {
      _showError(l10n.echecDeLaConnexionGoogle);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _showError(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      _showError(l10n.vousDevezAccepterLesConditions);
      return;
    }
    if (_selectedRole.first == UserRole.seller) {
      if (_idFrontBytes == null ||
          _idBackBytes == null ||
          _selfieBytes == null) {
        _showError(l10n.dossierKycIncomplet);
        return;
      }
    }
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.signUp(
        _nameController.text,
        _emailController.text,
        _passwordController.text,
        _selectedRole.first.name,
        phone: _phoneController.text,
        address: _addressController.text,
        idFront: _idFrontFile,
        idBack: _idBackFile,
        selfie: _selfieFile,
        referralCode: _referralController.text.trim(),
      );
      if (mounted && auth.pendingEmail != null) context.go('/verify');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    bool isSeller = _selectedRole.first == UserRole.seller;

    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        children: [
          // ── Decorative blobs ─────────────────────────────────────────────
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(size: 280, color: _primaryMid.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: 80,
            left: -80,
            child: _Blob(size: 240, color: _accent.withValues(alpha: 0.06)),
          ),

          // ── Main content ─────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),

                      // ── Logo + Brand ─────────────────────────────────────
                      Center(
                        child: Column(
                          children: [
                            Hero(
                              tag: 'logo',
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_primary, _primaryMid],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _primary.withValues(alpha: 0.30),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Image.asset(
                                  'assets/logo/logo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (c, e, s) => const Icon(
                                    Icons.person_add_rounded,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'PLEXUS',
                              style: TextStyle(
                                color: _primary,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.creezVotreCompteEnQuelques,
                              style: TextStyle(
                                  color: _textSub,
                                  fontSize: 12,
                                  letterSpacing: 0.3),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ── Role selector ────────────────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _primary.withValues(alpha: 0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            _RoleTab(
                              label: 'CLIENT',
                              icon: Icons.shopping_bag_outlined,
                              isSelected:
                                  _selectedRole.first == UserRole.client,
                              onTap: () => setState(
                                  () => _selectedRole = {UserRole.client}),
                            ),
                            _RoleTab(
                              label: 'VENDEUR',
                              icon: Icons.storefront_rounded,
                              isSelected:
                                  _selectedRole.first == UserRole.seller,
                              onTap: () => setState(
                                  () => _selectedRole = {UserRole.seller}),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Main card ────────────────────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: _primary.withValues(alpha: 0.07),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isSeller ? l10n.compteVendeur : l10n.compteClient,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _textMain,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isSeller
                                    ? l10n.completezVotreDossierPourOuvrir
                                    : l10n.rejoignezLaPlateformeEnQuelques,
                                style: const TextStyle(
                                    fontSize: 13, color: _textSub),
                              ),

                              const SizedBox(height: 28),

                              // Google (client only)
                              if (!isSeller) ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: OutlinedButton(
                                    onPressed: _isGoogleLoading
                                        ? null
                                        : _handleGoogleSignIn,
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      side: const BorderSide(
                                          color: _border, width: 1.5),
                                      backgroundColor: Colors.white,
                                    ),
                                    child: _isGoogleLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: _primary),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                  Icons.g_mobiledata_rounded,
                                                  color: _primary,
                                                  size: 30),
                                              const SizedBox(width: 12),
                                              Flexible(
                                                child: Text(
                                                  l10n.continuerAvecGoogle,
                                                  style: TextStyle(
                                                    color: _textMain,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(children: [
                                  const Expanded(
                                      child: Divider(color: _border)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                    child: Text(
                                      'OU',
                                      style: TextStyle(
                                        color: _textSub.withValues(alpha: 0.7),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                      child: Divider(color: _border)),
                                ]),
                                const SizedBox(height: 20),
                              ],

                              // Nom complet
                              _FieldLabel(label: l10n.nomComplet),
                              const SizedBox(height: 8),
                              _styledField(
                                  controller: _nameController,
                                  hint: l10n.jeanDupont,
                                  icon: Icons.person_outline_rounded),

                              const SizedBox(height: 18),

                              // Email
                              _FieldLabel(label: l10n.adresseEMail),
                              const SizedBox(height: 8),
                              _styledField(
                                  controller: _emailController,
                                  hint: l10n.exempleDomaineCom,
                                  icon: Icons.alternate_email_rounded,
                                  keyboardType: TextInputType.emailAddress),

                              // Seller-specific fields
                              if (isSeller) ...[
                                const SizedBox(height: 18),
                                _FieldLabel(label: l10n.telephone),
                                const SizedBox(height: 8),
                                _styledField(
                                    controller: _phoneController,
                                    hint: l10n.t2376xxXxxXxx,
                                    icon: Icons.phone_android_rounded,
                                    keyboardType: TextInputType.phone),

                                const SizedBox(height: 18),
                                _FieldLabel(
                                    label: l10n.localisationDeLaBoutique),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _addressController,
                                  style: const TextStyle(
                                      color: _textMain,
                                      fontWeight: FontWeight.w500),
                                  decoration: _inputDecoration(
                                    hint: l10n.rueVillePays,
                                    icon: Icons.location_on_outlined,
                                    suffix: _isGettingLocation
                                        ? const Padding(
                                            padding: EdgeInsets.all(14),
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: _primary),
                                            ),
                                          )
                                        : IconButton(
                                            icon: const Icon(
                                                Icons.my_location_rounded,
                                                color: _primary,
                                                size: 20),
                                            onPressed: _getCurrentLocation,
                                          ),
                                  ),
                                  validator: (v) =>
                                      v!.isEmpty ? l10n.requis : null,
                                ),

                                const SizedBox(height: 28),

                                // KYC section
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      l10n.documentsKycRequis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _primary,
                                        fontSize: 10,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 6),
                                Text(
                                  l10n.cesDocumentsSontNecessairesPour,
                                  style:
                                      TextStyle(fontSize: 11, color: _textSub),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _UploadBox(
                                        label: "SELFIE",
                                        sublabel: l10n.votreVisage,
                                        icon:
                                            Icons.face_retouching_natural,
                                        bytes: _selfieBytes,
                                        onTap: () =>
                                            _showImagePickerOptions(false,
                                                isSelfie: true),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _UploadBox(
                                        label: "RECTO",
                                        sublabel: l10n.cniPasseport,
                                        icon: Icons.credit_card_rounded,
                                        bytes: _idFrontBytes,
                                        onTap: () =>
                                            _showImagePickerOptions(true),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _UploadBox(
                                        label: "VERSO",
                                        sublabel: l10n.dosDuDoc,
                                        icon: Icons.flip_rounded,
                                        bytes: _idBackBytes,
                                        onTap: () =>
                                            _showImagePickerOptions(false),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Password
                              _FieldLabel(label: l10n.motDePasse),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(
                                    color: _textMain,
                                    fontWeight: FontWeight.w500),
                                decoration: _inputDecoration(
                                  hint: '••••••••',
                                  icon: Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: _textSub,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Referral
                              _FieldLabel(
                                  label: l10n.codeParrainageOptionnel),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _referralController,
                                style: const TextStyle(
                                    color: _textMain,
                                    fontWeight: FontWeight.w500),
                                decoration: _inputDecoration(
                                  hint: l10n.xxxxXxxx,
                                  icon: Icons.card_giftcard_rounded,
                                ),
                                validator: null,
                              ),

                              const SizedBox(height: 24),

                              // Terms
                              Container(
                                decoration: BoxDecoration(
                                  color: _acceptedTerms
                                      ? _primary.withValues(alpha: 0.04)
                                      : _surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _acceptedTerms
                                        ? _primary.withValues(alpha: 0.2)
                                        : _border,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _acceptedTerms,
                                      onChanged: (v) =>
                                          setState(() => _acceptedTerms = v!),
                                      activeColor: _primary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(5)),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _showLegalDocs,
                                        child: Text(
                                          l10n.jAccepteLesConditionsLegales,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _primaryMid,
                                            fontWeight: FontWeight.w500,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: _primaryMid,
                                          ),
                                          softWrap: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // Submit button
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient:
                                        (_isLoading || !_acceptedTerms)
                                            ? null
                                            : const LinearGradient(
                                                colors: [_primary, _primaryMid],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                    color: (_isLoading || !_acceptedTerms)
                                        ? _border
                                        : null,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow:
                                        (_isLoading || !_acceptedTerms)
                                            ? []
                                            : [
                                                BoxShadow(
                                                  color: _primary
                                                      .withValues(alpha: 0.35),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed:
                                        (_isLoading || !_acceptedTerms)
                                            ? null
                                            : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : Text(
                                            l10n.creerMonCompte,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              fontSize: 14,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Login link
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              l10n.dejaUnCompte,
                              style:
                                  TextStyle(color: _textSub, fontSize: 14),
                            ),
                            GestureDetector(
                              onTap: () => context.go('/login'),
                              child: Text(
                                l10n.seConnecter2,
                                style: TextStyle(
                                  color: _primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  decoration: TextDecoration.underline,
                                  decorationColor: _primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Widget _styledField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style:
          const TextStyle(color: _textMain, fontWeight: FontWeight.w500),
      decoration: _inputDecoration(hint: hint, icon: icon),
      validator: (v) => v!.isEmpty ? l10n.requis : null,
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: _textSub.withValues(alpha: 0.5), fontSize: 14),
      prefixIcon: Icon(icon, color: _textSub, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryMid, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFFEF4444), width: 2),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
        letterSpacing: 0.1,
      ),
    );
  }
}

class _RoleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1A237E)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF1A237E).withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadBox extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Uint8List? bytes;
  final VoidCallback onTap;

  const _UploadBox({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.bytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasImage = bytes != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 100,
        decoration: BoxDecoration(
          color:
              hasImage ? Colors.transparent : const Color(0xFFF4F6FB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage
                ? const Color(0xFF3949AB).withValues(alpha: 0.4)
                : const Color(0xFFE2E8F0),
            width: hasImage ? 2 : 1.5,
          ),
        ),
        child: hasImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(bytes!, fit: BoxFit.cover),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.5),
                              Colors.transparent
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF1A237E).withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon,
                        size: 20,
                        color: const Color(0xFF1A237E).withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A237E),
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: const TextStyle(
                        fontSize: 8, color: Color(0xFF64748B)),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}