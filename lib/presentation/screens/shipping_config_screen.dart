import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:plexus/core/api_config.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/constants/countries.dart';
import 'package:plexus/l10n/l10n.dart';

// NOUVEAU — écran vendeur : configuration de la grille de frais de livraison
// (local / national / régional / international) + exceptions par pays.
// Alimente computeShippingFee côté backend, appelé automatiquement à la
// création de chaque commande.
class ShippingConfigScreen extends StatefulWidget {
  const ShippingConfigScreen({super.key});

  @override
  State<ShippingConfigScreen> createState() => _ShippingConfigScreenState();
}

class _ShippingConfigScreenState extends State<ShippingConfigScreen> {
  static const Color _navy = Color(0xFF0D1B4B);
  static const Color _accent = Color(0xFF4A6CF7);
  static const Color _surface = Color(0xFFF4F6FF);
  static const Color _textMuted = Color(0xFF8A94B2);

  final _localC = TextEditingController();
  final _nationalC = TextEditingController();
  final _regionalC = TextEditingController();
  final _internationalC = TextEditingController();

  List<Map<String, dynamic>> _exceptions = []; // [{country, price}]

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchConfig();
  }

  @override
  void dispose() {
    _localC.dispose();
    _nationalC.dispose();
    _regionalC.dispose();
    _internationalC.dispose();
    super.dispose();
  }

  Future<void> _fetchConfig() async {
    final userId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.id;
    if (userId == null) return;

    try {
      final res = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/users/$userId/shipping-config'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final cfg = data['shippingConfig'] ?? {};
        _localC.text = '${cfg['local'] ?? 0}';
        _nationalC.text = '${cfg['national'] ?? 0}';
        _regionalC.text = '${cfg['regional'] ?? 0}';
        _internationalC.text = '${cfg['international'] ?? 0}';
        final rawExceptions = (cfg['exceptions'] as List?) ?? [];
        _exceptions = rawExceptions
            .map((e) => {
          'country': e['country'] ?? '',
          'price': e['price'] ?? 0,
        })
            .toList()
            .cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Erreur chargement config livraison: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    final userId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      final res = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/users/$userId/shipping-config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'local': double.tryParse(_localC.text) ?? 0,
          'national': double.tryParse(_nationalC.text) ?? 0,
          'regional': double.tryParse(_regionalC.text) ?? 0,
          'international': double.tryParse(_internationalC.text) ?? 0,
          'exceptions': _exceptions,
        }),
      );
      if (mounted) {
        if (res.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.fraisDeLivraisonEnregistres),
            backgroundColor: Color(0xFF00B386),
          ));
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.erreurDEnregistrement)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.erreurReseau)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addException() {
    String? country;
    final priceC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(l10n.ajouterUneException,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: country,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.pays2),
                items: kCountries.entries
                    .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(trCountry(e.key))))
                    .toList(),
                onChanged: (v) => setDialogState(() => country = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: l10n.fraisDeLivraison3),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.annuler),
            ),
            ElevatedButton(
              onPressed: () {
                final price = double.tryParse(priceC.text);
                if (country == null || price == null) return;
                setState(() {
                  _exceptions.add({'country': country, 'price': price});
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _navy),
              child:
              Text(l10n.ajouter, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(l10n.fraisDeLivraison,
            style: TextStyle(
                color: _navy,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1.5)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                l10n.cesFraisSontAjoutesAutomatiquement,
                style: TextStyle(
                    fontSize: 12.5, color: _navy, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            _zoneField(l10n.livraisonLocaleMemeVille, _localC),
            const SizedBox(height: 14),
            _zoneField(l10n.livraisonNationaleMemePays, _nationalC),
            const SizedBox(height: 14),
            _zoneField(
                l10n.livraisonRegionaleMemeContinent, _regionalC),
            const SizedBox(height: 14),
            _zoneField(l10n.livraisonInternationale, _internationalC),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.exceptionsParPays,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _navy)),
                TextButton.icon(
                  onPressed: _addException,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.ajouter),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_exceptions.isEmpty)
              Text(
                  l10n.aucuneExceptionUtileSiUn,
                  style: TextStyle(fontSize: 12, color: _textMuted)),
            ..._exceptions.asMap().entries.map((entry) {
              final i = entry.key;
              final ex = entry.value;
              final countryName =
                  trCountry(ex['country']?.toString());
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEBEFF8)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(countryName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13))),
                    Text('\$${ex['price']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _accent)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: Colors.redAccent),
                      onPressed: () =>
                          setState(() => _exceptions.removeAt(i)),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveConfig,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Text('ENREGISTRER',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixText: '\$ ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEBEFF8)),
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}