import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plexus/core/api_config.dart';
import 'package:plexus/core/http_auth.dart' as http;
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/services/escrow_pay_service.dart';
import 'package:plexus/l10n/l10n.dart';

class DisputeScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const DisputeScreen({required this.order, super.key});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen>
    with SingleTickerProviderStateMixin {
  final _descriptionController = TextEditingController();
  String _selectedMotif = 'Produit non conforme';

  final List<XFile> _photoFiles = [];
  final List<Uint8List> _photoBytes = [];
  XFile? _videoFile;
  bool _isSubmitting = false;

  final ImagePicker _picker = ImagePicker();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // ─── Palette ─────────────────────────────────────────────────────────────
  static const Color _primary    = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _danger     = Color(0xFFEF4444);
  static const Color _dangerBg   = Color(0xFFFEF2F2);
  static const Color _dangerBdr  = Color(0xFFFECACA);
  static const Color _surface    = Color(0xFFF4F6FB);
  static const Color _border     = Color(0xFFE2E8F0);
  static const Color _textMain   = Color(0xFF0F172A);
  static const Color _textSub    = Color(0xFF64748B);

  static const List<String> _motifs = [
    'Produit non conforme',
    'Endommagé',
    'Colis vide',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ─── Backend logic (unchanged) ───────────────────────────────────────────

  Future<void> _pickImage() async {
    if (_photoFiles.length >= 3) return;
    final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _photoFiles.add(image);
        _photoBytes.add(bytes);
      });
    }
  }

  Future<void> _pickVideo() async {
    final XFile? video =
    await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) setState(() => _videoFile = video);
  }

  Future<void> _submitDispute() async {
    if (_descriptionController.text.isEmpty) {
      _showSnack(l10n.laDescriptionEstObligatoire, _danger,
          Icons.warning_amber_rounded);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final String orderId =
      (widget.order['_id'] ?? widget.order['id'] ?? '').toString();

      var request = http.MultipartRequest(
          'POST', Uri.parse('${ApiConfig.baseUrl}/disputes'));
      request.fields['orderId']      = orderId;
      request.fields['motif']        = _selectedMotif;
      request.fields['description']  = _descriptionController.text;

      for (int i = 0; i < _photoFiles.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
          'photos',
          _photoBytes[i],
          filename: 'photo_$i.jpg',
        ));
      }

      if (_videoFile != null) {
        final vBytes = await _videoFile!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'video',
          vBytes,
          filename: 'video.mp4',
        ));
      }

      var streamedResponse = await request.send();
      var res = await http.Response.fromStream(streamedResponse);

      if (res.statusCode == 201 || res.statusCode == 200) {
        // Commande payée via escrow : on ouvre aussi le litige ON-CHAIN (page Thirdweb).
        final String? escrowId = widget.order['escrowId']?.toString();
        if (mounted && escrowId != null && escrowId != 'null' && escrowId.isNotEmpty) {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          if (auth.token != null) {
            try {
              await EscrowPayService.open(
                orderId: orderId,
                token: auth.token!,
                action: EscrowAction.dispute,
              );
            } catch (e) {
              debugPrint('On-chain dispute not opened: $e');
            }
          }
        }
        if (mounted) {
          context.pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text(l10n.litigeOuvertAvecSucces,
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500)),
              ]),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        debugPrint("SERVER ERROR 500 BODY: ${res.body}");
        throw Exception(l10n.erreur('${res.statusCode}', '${res.body}'));
      }
    } catch (e) {
      debugPrint("DISPUTE ERROR: $e");
      if (mounted)
        _showSnack(l10n.echecVerifiezLesLogsBackend, _danger,
            Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border, width: 1.2),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 15, color: _textMain),
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          l10n.ouvrirUnLitige,
          style: TextStyle(
            color: _textMain,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Warning banner ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _dangerBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _dangerBdr, width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gavel_rounded,
                        color: _danger, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.procedureDeLitige,
                            style: TextStyle(
                              color: _danger,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            l10n.lesFondsSontBloquesPendant,
                            style: TextStyle(
                                color: _danger,
                                fontSize: 11,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Form card ───────────────────────────────────────────
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(label: l10n.motifDuLitige),
                    const SizedBox(height: 10),

                    // Motif chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _motifs.map((motif) {
                        final bool selected = _selectedMotif == motif;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedMotif = motif),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: selected ? _danger : _surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                selected ? _danger : _border,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              trData(motif),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : _textSub,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 22),

                    _SectionLabel(label: l10n.descriptionDetaillee),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 5,
                      style: const TextStyle(
                          color: _textMain,
                          fontWeight: FontWeight.w500,
                          fontSize: 14),
                      decoration: InputDecoration(
                        hintText:
                        l10n.decrivezPrecisementLeProblemeRencontre,
                        hintStyle: TextStyle(
                            color: _textSub.withOpacity(0.5),
                            fontSize: 13),
                        filled: true,
                        fillColor: _surface,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          const BorderSide(color: _border, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          const BorderSide(color: _border, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: _danger, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Photo evidence card ─────────────────────────────────
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _SectionLabel(label: l10n.preuvesPhotos),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _photoBytes.length >= 3
                                ? _danger.withOpacity(0.10)
                                : _surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_photoBytes.length}/3',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _photoBytes.length >= 3
                                  ? _danger
                                  : _textSub,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.ajoutezJusquA3Photos,
                      style: TextStyle(
                          fontSize: 11,
                          color: _textSub.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ...List.generate(
                          _photoBytes.length,
                              (index) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _photoBytes[index],
                                  width: 82,
                                  height: 82,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _photoFiles.removeAt(index);
                                    _photoBytes.removeAt(index);
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: _danger,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white,
                                        size: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_photoFiles.length < 3)
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                Border.all(color: _border, width: 1.5),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      color: _textSub, size: 24),
                                  SizedBox(height: 4),
                                  Text(l10n.ajouter,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: _textSub,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Video evidence card ─────────────────────────────────
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(label: l10n.preuveVideoOptionnel),
                    const SizedBox(height: 14),
                    if (_videoFile != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(12),
                          border:
                          Border.all(color: _border, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6)
                                    .withOpacity(0.10),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                  Icons.video_file_outlined,
                                  color: Color(0xFF3B82F6),
                                  size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _videoFile!.name,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _textMain,
                                    fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _videoFile = null),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                    color: _dangerBg,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded,
                                    color: _danger, size: 14),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _pickVideo,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _border,
                                width: 1.5,
                                style: BorderStyle.solid),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.videocam_outlined,
                                  color: _textSub, size: 26),
                              SizedBox(height: 6),
                              Text(l10n.appuyezPourAjouterUneVideo,
                                  style: TextStyle(
                                      color: _textSub,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Submit button ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _isSubmitting ? _border : _danger,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _isSubmitting
                        ? []
                        : [
                      BoxShadow(
                        color: _danger.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitDispute,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gavel_rounded,
                            color: Colors.white, size: 17),
                        SizedBox(width: 10),
                        Text(
                          l10n.envoyerLeLitige,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
        letterSpacing: 0.1,
      ),
    );
  }
}