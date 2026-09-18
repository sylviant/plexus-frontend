import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/api_config.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const ProductCard({required this.product, super.key});

  static const Color _navy     = Color(0xFF0D1B4B);
  static const Color _primary  = Color(0xFF1A237E);
  static const Color _textSub  = Color(0xFF64748B);
  static const Color _textMain = Color(0xFF334155);
  static const Color _green    = Color(0xFF16A34A);
  static const Color _red      = Color(0xFFEF4444);

  // ─── Emoji drapeau depuis code pays ISO 2 lettres (ex: "CM" → 🇨🇲) ────────
  static String _countryFlag(String code) {
    if (code.length != 2) return '';
    return code.toUpperCase().runes
        .map((r) => String.fromCharCode(r - 0x41 + 0x1F1E6))
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final String productId = (product['_id'] ?? product['id'] ?? '').toString();
    final String title     = product['title']    ?? 'Sans titre';
    final double price     = (product['price'] as num?)?.toDouble() ?? 0.0;
    final String imageUrl  = ApiConfig.getImageUrl(product['thumbnail'] ?? product['image']);

    // Statut (point 2) et pays (point 3)
    final String status  = product['status']        ?? '';  // 'En stock' ou 'Limité'
    final String country = product['sellerCountry'] ?? '';  // ex: 'CM', 'FR', 'CN'
    final bool   hasStatus = status == 'En stock' || status == 'Limité';

    return GestureDetector(
      onTap: () => context.push('/home/product/$productId'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEBEFF8), width: 1),
        ),
        // ── Colonne racine : PAS d'Expanded ici (pas de hauteur bornée dans
        // ce contexte — Row/SliverList) → la carte prend exactement la
        // hauteur nécessaire à tout son contenu, sans rien couper.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Image carrée ──────────────────────────────────────────────
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFF0F3FF),
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: Color(0xFF8A94B2),
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Infos produit (hauteur libre, jamais coupée) ────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [

                  // Titre du produit
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: _textMain,
                      height: 1.25,
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Prix
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Drapeau + indicatif
                  if (country.length == 2)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_countryFlag(country), style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          country.toUpperCase(),
                          style: const TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),

                  // Ticker vertical statut / délai de livraison — entièrement
                  // visible, transition lente et lisible.
                  if (hasStatus) ...[
                    const SizedBox(height: 6),
                    _VerticalTextTicker(
                      height: 17,
                      displayDuration: const Duration(milliseconds: 3600),
                      transitionDuration: const Duration(milliseconds: 550),
                      items: [
                        Text(
                          status,
                          key: const ValueKey('status'),
                          style: TextStyle(
                            color: status == 'En stock' ? _green : _red,
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                          ),
                        ),
                        const Text(
                          'Livré en maximum 14 jours',
                          key: ValueKey('delivery'),
                          style: TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ticker vertical (défilement type odomètre, lent et lisible) ─────────────
class _VerticalTextTicker extends StatefulWidget {
  final List<Widget> items;
  final double        height;
  final Duration      displayDuration;   // temps d'affichage de chaque texte
  final Duration      transitionDuration; // durée de la transition

  const _VerticalTextTicker({
    required this.items,
    required this.height,
    this.displayDuration    = const Duration(seconds: 3),
    this.transitionDuration = const Duration(milliseconds: 500),
  });

  @override
  State<_VerticalTextTicker> createState() => _VerticalTextTickerState();
}

class _VerticalTextTickerState extends State<_VerticalTextTicker> {
  int    _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(widget.displayDuration, (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % widget.items.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: widget.transitionDuration,
          switchInCurve:  Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) {
            final offsetAnim = Tween<Offset>(
              begin: const Offset(0, 1),
              end:   Offset.zero,
            ).animate(anim);
            return ClipRect(
              child: SlideTransition(
                position: offsetAnim,
                child: FadeTransition(opacity: anim, child: child),
              ),
            );
          },
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previousChildren, if (currentChild != null) currentChild],
          ),
          child: Align(
            key: ValueKey(_index),
            alignment: Alignment.centerLeft,
            child: widget.items[_index],
          ),
        ),
      ),
    );
  }
}