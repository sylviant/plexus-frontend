# Installation i18n Plexus (10 langues : fr, en, es, it, de, pt, nl, ja, zh, ar)

Les fichiers de traduction sont DÉJÀ générés (lib/l10n/app_localizations*.dart).
Il n'y a PAS de commande `flutter gen-l10n` à lancer.

## 1. Nettoyer l'ancienne version (si tu avais déjà copié mon premier zip)
- Supprime `l10n.yaml` (à la racine du projet).
- Supprime `lib/l10n/app_fr.arb` et `lib/l10n/app_en.arb`.
- Dans `pubspec.yaml`, supprime la ligne `generate: true` (section `flutter:`).

## 2. Copier
Copie le dossier `lib/` de ce zip dans ton projet (remplace les fichiers).

## 3. pubspec.yaml
```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: any      # garde la version déjà utilisée par ton projet
```
Puis : `flutter pub get` et `flutter run`.

## Utilisation
- Texte : `l10n.cle` ou `l10n.cle(arg)` (sans context).
- Valeur backend en français (catégorie, statut, motif, transporteur) : `trData(valeur)`.
- Pays : `trCountry('CM')`.
- Dates : `DateFormat.yMMMMd()`, `DateFormat.jm()` (adaptées à la langue et à la région).

Le dossier `lib/Nouveau dossier/` n'est pas modifié (copie de sauvegarde).
