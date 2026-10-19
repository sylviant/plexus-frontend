import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/l10n/l10n.dart';

class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  // ─── Palette ────────────────────────────────────────────────────────────────
  static const Color _bg         = Color(0xFF0F1117);
  static const Color _surface    = Color(0xFF1A1D27);
  static const Color _surfaceAlt = Color(0xFF21253A);
  static const Color _accent     = Color(0xFF4F6EF7);
  static const Color _textPri    = Color(0xFFEBEDF5);
  static const Color _textSec    = Color(0xFF7B8097);
  static const Color _divider    = Color(0xFF252838);
  static const Color _green      = Color(0xFF34C97B);
  static const Color _orange     = Color(0xFFF5A623);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;
    final String referralCode = auth.myReferralCode ??
        "PLEXUS-${user?.id.substring(0, 5).toUpperCase() ?? 'USER'}";
    final String shareLink = "https://plexus-app.com/join/$referralCode";

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          children: [
            // ── Hero Icon ──────────────────────────────────────────────
            _buildHero(),
            const SizedBox(height: 32),

            // ── Title ──────────────────────────────────────────────────
            Text(
              l10n.invitezVosAmisGagnez,
              style: TextStyle(
                color: _textPri,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.partagezVotreCodeEtProfitez,
              style: TextStyle(
                  color: _textSec, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // ── Stats Row ──────────────────────────────────────────────
            Row(
              children: [
                _buildStatCard(l10n.amisInvites, "0", const Color(0xFF4F6EF7)),
                const SizedBox(width: 12),
                _buildStatCard(
                    l10n.gainsCumules,
                    "${auth.referralEarnings.toStringAsFixed(2)}\$",
                    _green),
              ],
            ),

            const SizedBox(height: 32),

            // ── Referral Code ──────────────────────────────────────────
            _buildSectionLabel(l10n.votreCodeUnique),
            const SizedBox(height: 12),
            _buildCodeCard(context, referralCode),

            const SizedBox(height: 28),

            // ── Share Button ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text:
                          l10n.rejoinsMoiSurPlexusUtilise('$referralCode', '$shareLink')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(l10n.lienDePartageCopie),
                      ]),
                      backgroundColor: _accent,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                },
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(l10n.inviterDesAmis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Savings Banner ─────────────────────────────────────────
            _buildSavingsBanner(auth),
          ],
        ),
      ),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      title: Text(
        l10n.parrainage,
        style: TextStyle(
          color: _textPri,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _divider),
      ),
    );
  }

  // ─── Hero ─────────────────────────────────────────────────────────────────────
  Widget _buildHero() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_orange.withOpacity(0.2), _orange.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: _orange.withOpacity(0.25), width: 1.5),
      ),
      child: const Icon(Icons.card_giftcard_rounded, size: 46, color: _orange),
    );
  }

  // ─── Section Label ────────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
            color: _textSec,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4),
      ),
    );
  }

  // ─── Stat Card ────────────────────────────────────────────────────────────────
  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.5)),
            const SizedBox(height: 5),
            Text(label,
                style: const TextStyle(
                    color: _textSec, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ─── Code Card ────────────────────────────────────────────────────────────────
  Widget _buildCodeCard(BuildContext context, String code) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              code,
              style: const TextStyle(
                color: _accent,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.copy_rounded, color: _accent, size: 18),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(children: [
                    Icon(Icons.copy, color: Colors.white, size: 14),
                    SizedBox(width: 8),
                    Text(l10n.codeCopie),
                  ]),
                  backgroundColor: _surface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Savings Banner ───────────────────────────────────────────────────────────
  Widget _buildSavingsBanner(AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.savings_outlined, color: _green, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.4),
                children: [
                  TextSpan(
                      text: l10n.economiesRealiseesGraceAuParrainage,
                      style: TextStyle(color: _textSec)),
                  TextSpan(
                    text:
                        "${auth.referralSavings.toStringAsFixed(2)}\$",
                    style: const TextStyle(
                        color: _green, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}