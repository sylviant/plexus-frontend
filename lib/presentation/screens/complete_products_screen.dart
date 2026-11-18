import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:plexus/core/api_config.dart';
import 'package:plexus/l10n/l10n.dart';

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
  final Map<String, String>   _statusMap   = {};
  final Map<String, String>   _countryMap  = {};

  static const Color _primary = Color(0xFF1A237E);
  static const Color _surface = Color(0xFFF4F6FB);
  static const Color _border  = Color(0xFFE2E8F0);
  static const Color _textMain= Color(0xFF0F172A);
  static const Color _textSub = Color(0xFF64748B);
  static const Color _green   = Color(0xFF16A34A);
  static const Color _red     = Color(0xFFEF4444);

  static List<DropdownMenuItem<String>> get _countryItems => [
    DropdownMenuItem(value: 'CM', child: Text(l10n.cm)),
    DropdownMenuItem(value: 'FR', child: Text(l10n.fr)),
    DropdownMenuItem(value: 'CN', child: Text(l10n.cn)),
    DropdownMenuItem(value: 'US', child: Text(l10n.us)),
    DropdownMenuItem(value: 'NG', child: Text(l10n.ng)),
    DropdownMenuItem(value: 'SN', child: Text(l10n.sn)),
    DropdownMenuItem(value: 'CI', child: Text(l10n.ci)),
    DropdownMenuItem(value: 'MA', child: Text(l10n.ma)),
    DropdownMenuItem(value: 'DZ', child: Text(l10n.dz)),
    DropdownMenuItem(value: 'GH', child: Text(l10n.gh)),
    DropdownMenuItem(value: 'ZA', child: Text(l10n.za)),
    DropdownMenuItem(value: 'GB', child: Text(l10n.gb)),
    DropdownMenuItem(value: 'DE', child: Text(l10n.de)),
    DropdownMenuItem(value: 'TR', child: Text(l10n.tr)),
    DropdownMenuItem(value: 'IN', child: Text(l10n.inLabel)),
    DropdownMenuItem(value: 'JP', child: Text(l10n.jp)),
    DropdownMenuItem(value: 'AE', child: Text(l10n.ae)),
    DropdownMenuItem(value: 'CD', child: Text(l10n.cd)),
    DropdownMenuItem(value: 'TG', child: Text(l10n.tg)),
    DropdownMenuItem(value: 'GA', child: Text(l10n.ga)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.veuillezRenseignerLeStatutEt),
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
        title: Text(l10n.completerVosProduits,
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _products.isEmpty
          ? Center(child: Text(l10n.toutEstAJour,
          style: TextStyle(color: _textSub, fontSize: 15)))
          : Column(children: [
        // Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: const Color(0xFFFFFBEB),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.certainsDeVosProduitsNecessitent,
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
                        Text(p['title'] ?? l10n.produit,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _textMain),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Row(children: [
                          // Statut
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _statusMap[id],
                              isDense: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                                filled: true, fillColor: _surface,
                              ),
                              items: [
                                DropdownMenuItem(value: 'En stock',
                                    child: Text(l10n.enStock, style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w700, fontSize: 11))),
                                DropdownMenuItem(value: 'Limité',
                                    child: Text(l10n.limite, style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700, fontSize: 11))),
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
                              initialValue: _countryMap[id],
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
                  : Text(l10n.enregistrerEtContinuer,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          ),
        ),
      ]),
    );
  }
}