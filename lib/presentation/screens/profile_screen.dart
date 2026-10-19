import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/l10n/l10n.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;

  // ─── Palette ────────────────────────────────────────────────────────────────
  static const Color _bg         = Color(0xFF0F1117);
  static const Color _surface    = Color(0xFF1A1D27);
  static const Color _surfaceAlt = Color(0xFF21253A);
  static const Color _accent     = Color(0xFF4F6EF7);
  static const Color _textPri    = Color(0xFFEBEDF5);
  static const Color _textSec    = Color(0xFF7B8097);
  static const Color _divider    = Color(0xFF252838);
  static const Color _green      = Color(0xFF34C97B);
  static const Color _red        = Color(0xFFEF5350);

  Future<void> _pickImage() async {
    final XFile? selected = await _picker.pickImage(source: ImageSource.gallery);
    if (selected != null) setState(() => _imageFile = selected);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Hero Header ────────────────────────────────────────────────
            _buildHeader(user, auth),

            const SizedBox(height: 32),

            // ── Menu Sections ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionLabel(l10n.general),
                  const SizedBox(height: 12),
                  _buildMenuGroup([
                    _TileData(Icons.person_outline_rounded,       l10n.editerLeProfil,       const Color(0xFF4F6EF7), () => context.push('/profile/edit')),
                    _TileData(Icons.card_giftcard_rounded,         l10n.parrainageGains,     const Color(0xFFF5A623), () => context.push('/profile/referral')),
                  ]),

                  const SizedBox(height: 28),
                  _buildSectionLabel(l10n.commandesAchats),
                  const SizedBox(height: 12),
                  _buildMenuGroup([
                    _TileData(Icons.shopping_bag_outlined,         l10n.historiqueDesAchats,  const Color(0xFF34C97B), () => context.push('/profile/orders')),
                    _TileData(Icons.favorite_outline_rounded,      l10n.mesFavoris,            const Color(0xFFEF5350), () => context.push('/profile/favorites')),
                  ]),

                  const SizedBox(height: 28),
                  _buildSectionLabel(l10n.paiement),
                  const SizedBox(height: 12),
                  _buildMenuGroup([
                    _TileData(Icons.account_balance_wallet_outlined, l10n.portefeuillesCrypto, const Color(0xFF9B8EF7), () => context.push('/profile/payment-methods')),
                    _TileData(Icons.location_on_outlined,           l10n.adressesDeLivraison, const Color(0xFFEF5350), () => context.push('/profile/address')), // LIEN CORRIGÉ
                  ]),

                  const SizedBox(height: 36),

                  // ── Logout ───────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => auth.logout(),
                      icon: const Icon(Icons.logout_rounded, size: 18, color: _red),
                      label: Text(l10n.deconnexion,
                          style: TextStyle(
                              color: _red,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.3)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _red.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Hero Header ─────────────────────────────────────────────────────────────
  Widget _buildHeader(dynamic user, AuthProvider auth) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            children: [
              // ── Top Row ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.monCompte,
                    style: TextStyle(
                      color: _textPri,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: _surfaceAlt,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: _divider),
                      ),
                      child: const Icon(Icons.settings_suggest_rounded,
                          color: _textSec, size: 18),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── Avatar ────────────────────────────────────────────────
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F6EF7), Color(0xFF9B8EF7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: _surface, shape: BoxShape.circle),
                      child: CircleAvatar(
                        radius: 48,
                        backgroundColor: _surfaceAlt,
                        backgroundImage: _imageFile != null
                            ? FileImage(File(_imageFile!.path))
                            : (user?.profileImage != null
                                ? NetworkImage(user!.profileImage!)
                                : null) as ImageProvider?,
                        child: (_imageFile == null && user?.profileImage == null)
                            ? const Icon(Icons.person_rounded,
                                size: 44, color: _textSec)
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2, right: 2,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: _surface, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text(
                user?.firstName ?? l10n.utilisateurPlexus,
                style: const TextStyle(
                  color: _textPri,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _green.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                          color: _green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(l10n.profilActif,
                        style: TextStyle(
                            color: _green,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Section Label ────────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
          color: _textSec,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4),
    );
  }

  // ─── Menu Group ───────────────────────────────────────────────────────────────
  Widget _buildMenuGroup(List<_TileData> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: List.generate(tiles.length, (i) {
          final t = tiles[i];
          final isLast = i == tiles.length - 1;
          return Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.vertical(
                    top: i == 0 ? const Radius.circular(16) : Radius.zero,
                    bottom: isLast ? const Radius.circular(16) : Radius.zero,
                  ),
                  onTap: t.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: t.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(t.icon, color: t.color, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(t.title,
                              style: const TextStyle(
                                  color: _textPri,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 13, color: _textSec),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Container(
                    height: 1,
                    color: _divider,
                    margin: const EdgeInsets.only(left: 68)),
            ],
          );
        }),
      ),
    );
  }
}

class _TileData {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  const _TileData(this.icon, this.title, this.color, this.onTap);
}