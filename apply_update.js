// apply_update.js - a lancer a la racine du projet PLEXUS :
//   node apply_update.js <dossier-du-depot-plexus-frontend-clone>
const fs = require('fs');
const path = require('path');

const repo = process.argv[2];
if (!repo || !fs.existsSync(path.join(repo, 'lib/blockchain/v2'))) {
  console.error('Usage : node apply_update.js <dossier plexus-frontend clone (commit 1314c97)>');
  process.exit(1);
}
const BACKUP = '_backup_avant_maj'; // tes anciens fichiers y sont sauvegardes avant d'etre remplaces

function copy(rel) {
  const dst = rel;
  if (fs.existsSync(dst)) {
    const b = path.join(BACKUP, rel);
    fs.mkdirSync(path.dirname(b), { recursive: true });
    fs.copyFileSync(dst, b);
  }
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(path.join(repo, rel), dst);
}
function copyDir(rel) {
  for (const e of fs.readdirSync(path.join(repo, rel), { withFileTypes: true })) {
    const r = rel + '/' + e.name;
    e.isDirectory() ? copyDir(r) : copy(r);
  }
}

// 1) Fichiers identiques a l'ancienne base chez toi : on prend la version du commit
const files = [
  'analysis_options.yaml',
  'lib/Nouveau dossier/add_product_screen.dart',
  'lib/Nouveau dossier/home_screen.dart',
  'lib/Nouveau dossier/product_card.dart',
  'lib/Nouveau dossier/product_detail_screen.dart',
  'lib/core/api_config.dart',
  'lib/core/providers/cart_provider.dart',
  'lib/core/providers/category_provider.dart',
  'lib/core/providers/favorite_provider.dart',
  'lib/core/providers/notification_provider.dart',
  'lib/core/router.dart',
  'lib/l10n/app_localizations.dart',
  'lib/main.dart',
  'lib/presentation/scaffold_with_nav_bar.dart',
  'lib/presentation/screens/add_product_screen.dart',
  'lib/presentation/screens/ai_chat_screen.dart',
  'lib/presentation/screens/auth/forgot_password_screen.dart',
  'lib/presentation/screens/auth/login_screen.dart',
  'lib/presentation/screens/auth/reset_password_screen.dart',
  'lib/presentation/screens/auth/signup_screen.dart',
  'lib/presentation/screens/auth/verification_screen.dart',
  'lib/presentation/screens/cart_screen.dart',
  'lib/presentation/screens/categories_screen.dart',
  'lib/presentation/screens/category_products_screen.dart',
  'lib/presentation/screens/chat_screen.dart',
  'lib/presentation/screens/complete_products_screen.dart',
  'lib/presentation/screens/confirmation_screen.dart',
  'lib/presentation/screens/edit_profile_screen.dart',
  'lib/presentation/screens/favorites_screen.dart',
  'lib/presentation/screens/home_screen.dart',
  'lib/presentation/screens/messages_screen.dart',
  'lib/presentation/screens/notifications_screen.dart',
  'lib/presentation/screens/order_detail_screen.dart',
  'lib/presentation/screens/order_history_screen.dart',
  'lib/presentation/screens/order_success_screen.dart',
  'lib/presentation/screens/payment_methods_screen.dart',
  'lib/presentation/screens/profile_screen.dart',
  'lib/presentation/screens/referral_screen.dart',
  'lib/presentation/screens/seller_hub_screen.dart',
  'lib/presentation/screens/seller_profile_screen.dart',
  'lib/presentation/screens/shipping_address_screen.dart',
  'lib/presentation/screens/shipping_config_screen.dart',
  'lib/presentation/screens/splash_screen.dart',
  'lib/presentation/screens/user_type_selection_screen.dart',
  'lib/presentation/widgets/category_list.dart',
  'lib/presentation/widgets/product_card.dart',
  'lib/presentation/widgets/product_card_widget.dart',
  'lib/presentation/widgets/related_product_card.dart',
  'test/widget_test.dart',
];
files.forEach(copy);

// 2) Nouveautes : module V2, banc de test, tests
['lib/blockchain/v2', 'lib/dev', 'test/blockchain', 'test/fixtures'].forEach(copyDir);
copy('lib/main_wallet_test.dart');

// 3) Migration mecanique (import material_ui, withOpacity -> withValues, _ __ ___ -> _) : rien d'autre n'est touche.
//    Tes 3 fichiers modifies + les 2 fichiers du banc de test, que le depot n'a pas migres lui-meme.
const mine = [
  'lib/core/providers/socket_provider.dart',
  'lib/presentation/screens/dispute_screen.dart',
  'lib/presentation/screens/product_detail_screen.dart',
  'lib/dev/wallet_test_page.dart',
  'lib/main_wallet_test.dart',
];
for (const f of mine) {
  const b = path.join(BACKUP, f);
  fs.mkdirSync(path.dirname(b), { recursive: true });
  fs.copyFileSync(f, b);
  let s = fs.readFileSync(f, 'utf8');
  s = s.replace('package:flutter/material.dart', 'package:material_ui/material_ui.dart');
  s = s.replace(/\.withOpacity\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)/g, '.withValues(alpha: $1)');
  s = s.replace(/(?<=[(,]\s*)_{2,3}(?=\s*[,)])/g, '_');
  fs.writeFileSync(f, s);
}
console.log('Termine : ' + files.length + ' fichiers remplaces, module V2 + tests ajoutes, ' + mine.length + ' fichiers migres (import material_ui).');
console.log('Anciennes versions sauvegardees dans ./' + BACKUP);