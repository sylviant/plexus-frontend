import 'package:flutter/material.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:plexus/core/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/constants/countries.dart';
import 'dart:convert';

class ShippingAddressScreen extends StatefulWidget {
  const ShippingAddressScreen({super.key});

  @override
  State<ShippingAddressScreen> createState() => _ShippingAddressScreenState();
}

class _ShippingAddressScreenState extends State<ShippingAddressScreen>
    with SingleTickerProviderStateMixin {
  // ─── Votre Palette (Inchangée) ─────────────────────────
  static const Color _navy = Color(0xFF0D1B4B);
  static const Color _accent = Color(0xFF4A6CF7);
  static const Color _surface = Color(0xFFF4F6FF);
  static const Color _textMuted = Color(0xFF8A94B2);

  final _addressController = TextEditingController();
  bool _isLoading = false;
  bool _isGettingLocation = false;
  bool _isFocused = false;

  // NOUVEAU — code pays ISO2 (ex: "CM", "FR") utilisé pour calculer
  // automatiquement les frais de livraison côté backend.
  String? _countryCode;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _fetchCurrentAddress(); // Appel au chargement
  }

  @override
  void dispose() {
    _animController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // RÉCUPÉRATION DE L'ADRESSE DEPUIS LE BACKEND
  Future<void> _fetchCurrentAddress() async {
    final userId = Provider.of<AuthProvider>(context, listen: false).currentUser?.id;
    if (userId == null) return;
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/users/$userId'));
      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        if (mounted) {
          setState(() {
            if (userData['address'] != null) {
              _addressController.text = userData['address'];
            }
            if (userData['country'] != null &&
                (userData['country'] as String).isNotEmpty) {
              _countryCode = userData['country'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Erreur lors de la récupération de l'adresse: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Services de localisation désactivés.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied)
          throw 'Permissions refusées.';
      }

      Position position = await Geolocator.getCurrentPosition();
      List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _addressController.text =
          "${place.street}, ${place.locality}, ${place.country}";
          // NOUVEAU — capture directe du code ISO2 fourni par le géocodage,
          // plus fiable qu'une déduction depuis le texte de l'adresse.
          if (place.isoCountryCode != null &&
              place.isoCountryCode!.isNotEmpty) {
            _countryCode = place.isoCountryCode;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // SAUVEGARDE ET MISE À JOUR DE L'ÉTAT LOCAL
  Future<void> _saveAddress() async {
    if (_addressController.text.isEmpty) return;
    if (_countryCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sélectionnez votre pays.")),
      );
      return;
    }
    setState(() => _isLoading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.currentUser?.id;

    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/users/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'address': _addressController.text,
          'country': _countryCode, // NOUVEAU
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Mise à jour de l'AuthProvider pour que l'app soit au courant du changement
        auth.updateLocalUserData(responseData['user'] ?? responseData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Adresse enregistrée !"),
              backgroundColor: Color(0xFF00B386),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur de sauvegarde.")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── LE RESTE DU BUILD (VOTRE DESIGN) EST CONSERVÉ À 100% ────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _fieldLabel("ADRESSE COMPLÈTE"),
                    const SizedBox(height: 10),
                    _buildAddressField(),
                    const SizedBox(height: 16),
                    _buildLocationButton(),
                    const SizedBox(height: 16),
                    _fieldLabel("PAYS"),
                    const SizedBox(height: 10),
                    _buildCountryDropdown(),
                    const SizedBox(height: 28),
                    _buildTip(),
                  ],
                ),
              ),
            ),
            _buildConfirmButton(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 16, color: _navy),
        ),
      ),
      title: const Text(
        "ADRESSE DE LIVRAISON",
        style: TextStyle(
          color: _navy,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          fontSize: 13,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: const Color(0xFFE8ECF8), height: 1),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1B4B), Color(0xFF1A2E6E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Où souhaitez-vous\nêtre livré ?",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Adresse par défaut pour vos commandes",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _textMuted,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }

  Widget _buildAddressField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isFocused ? _accent : const Color(0xFFEBEFF8),
          width: _isFocused ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _isFocused
                ? _accent.withOpacity(0.08)
                : Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: TextField(
          controller: _addressController,
          maxLines: 4,
          style: const TextStyle(
            color: _navy,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
          decoration: const InputDecoration(
            hintText: "Ex: 12 Rue de la Paix, Yaoundé, Cameroun",
            hintStyle: TextStyle(color: _textMuted, fontSize: 13),
            contentPadding: EdgeInsets.all(20),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  // NOUVEAU — sélecteur de pays (rempli auto par le GPS, modifiable à la main)
  Widget _buildCountryDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEBEFF8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          value: _countryCode,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: _accent),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: "Sélectionnez votre pays",
          ),
          style: const TextStyle(
            color: _navy,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          items: kCountries.entries
              .map((e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value),
          ))
              .toList(),
          onChanged: (value) => setState(() => _countryCode = value),
        ),
      ),
    );
  }

  Widget _buildLocationButton() {
    return GestureDetector(
      onTap: _isGettingLocation ? null : _getCurrentLocation,
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEBEFF8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isGettingLocation)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _accent),
              )
            else
              const Icon(Icons.my_location_rounded,
                  size: 18, color: _accent),
            const SizedBox(width: 10),
            const Text(
              "Utiliser ma position actuelle",
              style: TextStyle(
                color: _navy,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: _accent.withOpacity(0.8)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Cette adresse sera utilisée par défaut pour toutes vos commandes futures.",
              style: TextStyle(
                color: _textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEBEFF8))),
      ),
      child: GestureDetector(
        onTap: _isLoading ? null : _saveAddress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_navy, Color(0xFF2A4099)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _navy.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text(
                  "CONFIRMER L'ADRESSE",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}