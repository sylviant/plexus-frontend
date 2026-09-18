import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';

class CompleteProductsScreen extends StatefulWidget {
  final String sellerId;
  const CompleteProductsScreen({required this.sellerId, super.key});

  @override
  State<CompleteProductsScreen> createState() => _CompleteProductsScreenState();
}

class _CompleteProductsScreenState extends State<CompleteProductsScreen> {
  List<dynamic>         _products    = [];
  bool                  _isLoading   = true;
  bool                  _isSaving    = false;
  Map<String, String>   _statusMap   = {};
  Map<String, String>   _countryMap  = {};

  static const Color _primary = Color(0xFF1A237E);
  static const Color _surface = Color(0xFFF4F6FB);
  static const Color _border  = Color(0xFFE2E8F0);
  static const Color _textMain= Color(0xFF0F172A);
  static const Color _textSub = Color(0xFF64748B);
  static const Color _green   = Color(0xFF16A34A);
  static const Color _red     = Color(0xFFEF4444);

  static const List<DropdownMenuItem<String>> _countryItems = [
    DropdownMenuItem(value: 'CM', child: Text('🇨🇲 CM')),
    DropdownMenuItem(value: 'FR', child: Text('🇫🇷 FR')),
    DropdownMenuItem(value: 'CN', child: Text('🇨🇳 CN')),
    DropdownMenuItem(value: 'US', child: Text('🇺🇸 US')),
    DropdownMenuItem(value: 'NG', child: Text('🇳🇬 NG')),
    DropdownMenuItem(value: 'SN', child: Text('🇸🇳 SN')),
    DropdownMenuItem(value: 'CI', child: Text('🇨🇮 CI')),
    DropdownMenuItem(value: 'MA', child: Text('🇲🇦 MA')),
    DropdownMenuItem(value: 'DZ', child: Text('🇩🇿 DZ')),
    DropdownMenuItem(value: 'GH', child: Text('🇬🇭 GH')),
    DropdownMenuItem(value: 'ZA', child: Text('🇿🇦 ZA')),
    DropdownMenuItem(value: 'GB', child: Text('🇬🇧 GB')),
    DropdownMenuItem(value: 'DE', child: Text('🇩🇪 DE')),
    DropdownMenuItem(value: 'TR', child: Text('🇹🇷 TR')),
    DropdownMenuItem(value: 'IN', child: Text('🇮🇳 IN')),
    DropdownMenuItem(value: 'JP', child: Text('🇯🇵 JP')),
    DropdownMenuItem(value: 'AE', child: Text('🇦🇪 AE')),
    DropdownMenuItem(value: 'CD', child: Text('🇨🇩 CD')),
    DropdownMenuItem(value: 'TG', child: Text('🇹🇬 TG')),
    DropdownMenuItem(value: 'GA', child: Text('🇬🇦 GA')),
  ];

  @override
  void initState() {
    super.initState();
    _fetchIncomplete();
  }

  Future<void> _fetchIncomplete() async {
    try {
      final res = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/sellers/${widget.sellerId}/incomplete-products'));
      if (res.statusCode == 200 && mounted) {
        final list = json.decode(res.body) as List;
        setState(() {
          _products  = list;
          _isLoading = false;
          for (final p in list) {
            final id = p['_id'].toString();
            _statusMap[id]  = 'En stock';
            _countryMap[id] = 'CM';
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    // Vérifier que tout est renseigné
    for (final p in _products) {
      final id = p['_id'].toString();
      if (_statusMap[id] == null || _countryMap[id] == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Veuillez renseigner le statut et le pays pour tous les produits.'),
          backgroundColor: Colors.orange,
        ));
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final updates = _products.map((p) {
        final id = p['_id'].toString();
        return {'productId': id, 'status': _statusMap[id], 'sellerCountry': _countryMap[id]};
      }).toList();

      final res = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/sellers/${widget.sellerId}/complete-products'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'updates': updates}),
      );

      if (res.statusCode == 200 && mounted) {
        context.go('/home');
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Compléter vos produits',
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _products.isEmpty
          ? Center(child: Text('Tout est à jour !',
          style: TextStyle(color: _textSub, fontSize: 15)))
          : Column(children: [
        // Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: const Color(0xFFFFFBEB),
          child: Row(children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Certains de vos produits nécessitent un statut et un pays. Veuillez les compléter pour continuer.',
                style: TextStyle(color: Color(0xFF92400E), fontSize: 12, height: 1.4),
              ),
            ),
          ]),
        ),

        // Liste
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _products.length,
            itemBuilder: (_, i) {
              final p  = _products[i];
              final id = p['_id'].toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Row(children: [
                  // Miniature
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: p['thumbnail'] != null
                        ? Image.network(ApiConfig.getImageUrl(p['thumbnail']),
                        width: 56, height: 56, fit: BoxFit.cover)
                        : Container(width: 56, height: 56,
                        color: _surface,
                        child: const Icon(Icons.image_outlined, color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['title'] ?? 'Produit',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _textMain),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Row(children: [
                          // Statut
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _statusMap[id],
                              isDense: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                                filled: true, fillColor: _surface,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'En stock',
                                    child: Text('En stock', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w700, fontSize: 11))),
                                DropdownMenuItem(value: 'Limité',
                                    child: Text('Limité', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700, fontSize: 11))),
                              ],
                              onChanged: (v) => setState(() => _statusMap[id] = v!),
                              style: const TextStyle(fontSize: 12, color: _textMain),
                              dropdownColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Pays
                          SizedBox(
                            width: 90,
                            child: DropdownButtonFormField<String>(
                              value: _countryMap[id],
                              isDense: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                                filled: true, fillColor: _surface,
                              ),
                              items: _countryItems,
                              onChanged: (v) => setState(() => _countryMap[id] = v!),
                              style: const TextStyle(fontSize: 12, color: _textMain),
                              dropdownColor: Colors.white,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ]),
              );
            },
          ),
        ),

        // Bouton sauvegarder
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16,
              MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : const Text('ENREGISTRER ET CONTINUER',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          ),
        ),
      ]),
    );
  }
}