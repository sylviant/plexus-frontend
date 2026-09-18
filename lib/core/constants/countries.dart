// Liste compacte de pays (code ISO 3166-1 alpha-2 -> nom affiché en français).
// Utilisée pour calculer automatiquement les frais de livraison côté backend
// (voir computeShippingFee). Complète cette liste au besoin.
const Map<String, String> kCountries = {
  'CM': 'Cameroun', 'NG': 'Nigeria', 'SN': 'Sénégal', 'CI': "Côte d'Ivoire",
  'GA': 'Gabon', 'ML': 'Mali', 'TD': 'Tchad', 'CG': 'Congo',
  'CD': 'RD Congo', 'GH': 'Ghana', 'KE': 'Kenya', 'MA': 'Maroc',
  'TN': 'Tunisie', 'DZ': 'Algérie', 'BJ': 'Bénin', 'TG': 'Togo',
  'BF': 'Burkina Faso', 'NE': 'Niger', 'GN': 'Guinée', 'ZA': 'Afrique du Sud',
  'EG': 'Égypte', 'FR': 'France', 'BE': 'Belgique', 'CH': 'Suisse',
  'DE': 'Allemagne', 'GB': 'Royaume-Uni', 'ES': 'Espagne', 'IT': 'Italie',
  'PT': 'Portugal', 'NL': 'Pays-Bas', 'US': 'États-Unis', 'CA': 'Canada',
  'CN': 'Chine', 'AE': 'Émirats arabes unis', 'SA': 'Arabie saoudite',
  'IN': 'Inde', 'BR': 'Brésil', 'AU': 'Australie', 'TR': 'Turquie',
};