import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:plexus/l10n/app_localizations.dart';

export 'package:plexus/l10n/app_localizations.dart';

/// Gestion centralisée de la langue de l'application (i18n).
///
/// - La langue est déduite de la langue du téléphone (ou du navigateur sur Flutter Web).
/// - La zone géographique (code pays de la locale, ex. fr_CM, en_NG) est conservée
///   pour les formats de dates / nombres (Intl.defaultLocale).
/// - Si la langue du téléphone n'est pas traduite, la zone géographique décide :
///   pays francophone -> français, sinon -> anglais.
class L10n {
  L10n._();

  /// Langues disponibles (fichiers lib/l10n/app_localizations_XX.dart).
  static const Set<String> supportedLanguages = {'fr', 'en', 'es', 'it', 'de', 'pt', 'nl', 'ja', 'zh', 'ar'};

  /// Pays où le français est la langue de repli.
  static const Set<String> _francophoneZones = {
    'FR', 'BE', 'LU', 'MC', 'CH', 'CA', 'CM', 'SN', 'CI', 'GA', 'ML', 'TD', 'CG', 'CD',
    'BJ', 'TG', 'BF', 'NE', 'GN', 'MG', 'DZ', 'TN', 'MA', 'MR', 'HT', 'CF', 'DJ', 'KM',
    'BI', 'RW', 'GQ', 'SC', 'VU',
  };

  static Locale _locale = const Locale('fr');
  static AppLocalizations _current = lookupAppLocalizations(const Locale('fr'));

  static Locale get locale => _locale;
  static AppLocalizations get current => _current;

  /// Choisit la locale de l'application à partir d'une locale d'appareil.
  static Locale resolve(Locale? device) {
    final String? country = (device?.countryCode?.isEmpty ?? true) ? null : device!.countryCode;
    final String? lang = device?.languageCode;
    if (lang != null && supportedLanguages.contains(lang)) {
      return Locale(lang, country);
    }
    final bool francophone = country != null && _francophoneZones.contains(country);
    return Locale(francophone ? 'fr' : 'en', country);
  }

  /// Version "liste de langues préférées" (Android 13+, iOS, Web).
  static Locale resolveList(List<Locale>? locales) {
    if (locales == null || locales.isEmpty) return resolve(null);
    final String? zone = locales
        .map((l) => l.countryCode)
        .firstWhere((c) => c != null && c.isNotEmpty, orElse: () => null);
    for (final l in locales) {
      if (supportedLanguages.contains(l.languageCode)) {
        final String? c = (l.countryCode?.isNotEmpty ?? false) ? l.countryCode : zone;
        return Locale(l.languageCode, c);
      }
    }
    return resolve(locales.first);
  }

  /// À appeler dans main() avant runApp (après initializeDateFormatting()).
  static void initFromDevice() {
    apply(resolve(ui.PlatformDispatcher.instance.locale));
  }

  /// Applique une locale : textes + formats de dates/nombres.
  static void apply(Locale locale) {
    _locale = locale;
    _current = lookupAppLocalizations(locale);
    Intl.defaultLocale = locale.toString();
  }
}

/// Accès aux textes traduits sans BuildContext : `l10n.panier`.
AppLocalizations get l10n => L10n.current;

/// Traduit l'AFFICHAGE d'une valeur "métier" stockée en français côté backend
/// (catégories, sous-catégories, statuts, motifs de litige, transporteurs).
/// La valeur envoyée/stockée n'est JAMAIS modifiée : seule l'étiquette affichée change.
/// Les valeurs inconnues (ex. nouvelle catégorie créée côté serveur) sont renvoyées telles quelles.
String trData(String? value) {
  if (value == null) return '';
  switch (value) {
      case 'Tout':
        return l10n.dataTout;
      case 'Maison':
        return l10n.dataMaison;
      case 'Beauté':
        return l10n.dataBeaute;
      case 'Électronique':
        return l10n.dataElectronique;
      case 'Mode':
        return l10n.dataMode;
      case 'Livres':
        return l10n.dataLivres;
      case 'Sports':
        return l10n.dataSports;
      case 'Alimentation':
        return l10n.dataAlimentation;
      case 'Automobile':
        return l10n.dataAutomobile;
      case 'Jouets':
        return l10n.dataJouets;
      case 'Jardin':
        return l10n.dataJardin;
      case 'Femme':
        return l10n.dataFemme;
      case 'Homme':
        return l10n.dataHomme;
      case 'Enfants':
        return l10n.dataEnfants;
      case 'Accessoires':
        return l10n.dataAccessoires;
      case 'Électricité':
        return l10n.dataElectricite;
      case 'Quincaillerie':
        return l10n.dataQuincaillerie;
      case 'Smartphones':
        return l10n.dataSmartphones;
      case 'Informatique':
        return l10n.dataInformatique;
      case 'Mobilier':
        return l10n.dataMobilier;
      case 'Meubles':
        return l10n.dataMeubles;
      case 'Décoration':
        return l10n.dataDecoration;
      case 'Électroménager':
        return l10n.dataElectromenager;
      case 'Maquillage':
        return l10n.dataMaquillage;
      case 'Soins':
        return l10n.dataSoins;
      case 'Parfums':
        return l10n.dataParfums;
      case 'Hygiène':
        return l10n.dataHygiene;
      case 'Romans':
        return l10n.dataRomans;
      case 'Scolaire':
        return l10n.dataScolaire;
      case 'Dév. Personnel':
        return l10n.dataDevPersonnel;
      case 'Fitness':
        return l10n.dataFitness;
      case 'Football':
        return l10n.dataFootball;
      case 'Outdoor':
        return l10n.dataOutdoor;
      case 'Combat':
        return l10n.dataCombat;
      case 'Épicerie':
        return l10n.dataEpicerie;
      case 'Boissons':
        return l10n.dataBoissons;
      case 'Frais':
        return l10n.dataFrais;
      case 'Surgelés':
        return l10n.dataSurgeles;
      case 'Pièces':
        return l10n.dataPieces;
      case 'Entretien':
        return l10n.dataEntretien;
      case 'Pneus':
        return l10n.dataPneus;
      case 'Jeux de société':
        return l10n.dataJeuxDeSociete;
      case 'Éveil':
        return l10n.dataEveil;
      case 'Consoles':
        return l10n.dataConsoles;
      case 'Figurines':
        return l10n.dataFigurines;
      case 'Outils':
        return l10n.dataOutils;
      case 'Plantes':
        return l10n.dataPlantes;
      case 'Mobilier de jardin':
        return l10n.dataMobilierDeJardin;
      case 'Produit non conforme':
        return l10n.dataProduitNonConforme;
      case 'Endommagé':
        return l10n.dataEndommage;
      case 'Colis vide':
        return l10n.dataColisVide;
      case 'Main propre':
        return l10n.dataMainPropre;
      case 'Autre':
        return l10n.dataAutre;
      case 'En stock':
        return l10n.enStock;
      case 'Limité':
        return l10n.limite;
    default:
      return value;
  }
}

/// Traduit à l'AFFICHAGE les messages "système" générés par l'application et stockés
/// en français sur le serveur (réception, livraison, expédition). Les messages écrits par
/// les utilisateurs ne sont jamais modifiés.
String trChatText(String text) {
  const String prefix = '📢 SYSTÈME : ';
  if (!text.startsWith(prefix)) return text;
  final String body = text.substring(prefix.length);
  final String head = l10n.chatSystemPrefix;
  if (body == 'Réception confirmée. Fonds libérés.') {
    return head + l10n.chatReceiptConfirmed;
  }
  if (body == 'Vendeur confirme la livraison. Attente acheteur.') {
    return head + l10n.chatSellerDelivered;
  }
  final RegExpMatch? m = RegExp(
    r'^📦 \*COLIS EXPÉDIÉ\* :\n• Transporteur: ([^\n]*)(?:\n• Suivi: ([^\n]*))?$',
  ).firstMatch(body);
  if (m != null) {
    String out = head + l10n.chatShipped(trData(m.group(1)));
    final String? tracking = m.group(2);
    if (tracking != null && tracking.isNotEmpty) out += l10n.chatTracking(tracking);
    return out;
  }
  return text;
}

/// Nom d'un pays (code ISO 3166-1 alpha-2) dans la langue de l'application.
/// Le code envoyé/stocké reste inchangé ; seul l'affichage est traduit.
String trCountry(String? code) {
  if (code == null) return '';
  switch (code.toUpperCase()) {
    case 'CM':
      return l10n.countryCm;
    case 'NG':
      return l10n.countryNg;
    case 'SN':
      return l10n.countrySn;
    case 'CI':
      return l10n.countryCi;
    case 'GA':
      return l10n.countryGa;
    case 'ML':
      return l10n.countryMl;
    case 'TD':
      return l10n.countryTd;
    case 'CG':
      return l10n.countryCg;
    case 'CD':
      return l10n.countryCd;
    case 'GH':
      return l10n.countryGh;
    case 'KE':
      return l10n.countryKe;
    case 'MA':
      return l10n.countryMa;
    case 'TN':
      return l10n.countryTn;
    case 'DZ':
      return l10n.countryDz;
    case 'BJ':
      return l10n.countryBj;
    case 'TG':
      return l10n.countryTg;
    case 'BF':
      return l10n.countryBf;
    case 'NE':
      return l10n.countryNe;
    case 'GN':
      return l10n.countryGn;
    case 'ZA':
      return l10n.countryZa;
    case 'EG':
      return l10n.countryEg;
    case 'FR':
      return l10n.countryFr;
    case 'BE':
      return l10n.countryBe;
    case 'CH':
      return l10n.countryCh;
    case 'DE':
      return l10n.countryDe;
    case 'GB':
      return l10n.countryGb;
    case 'ES':
      return l10n.countryEs;
    case 'IT':
      return l10n.countryIt;
    case 'PT':
      return l10n.countryPt;
    case 'NL':
      return l10n.countryNl;
    case 'US':
      return l10n.countryUs;
    case 'CA':
      return l10n.countryCa;
    case 'CN':
      return l10n.countryCn;
    case 'AE':
      return l10n.countryAe;
    case 'SA':
      return l10n.countrySa;
    case 'IN':
      return l10n.countryIn;
    case 'BR':
      return l10n.countryBr;
    case 'AU':
      return l10n.countryAu;
    case 'TR':
      return l10n.countryTr;
    case 'JP':
      return l10n.countryJp;
    default:
      return code;
  }
}
