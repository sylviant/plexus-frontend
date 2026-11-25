// node apply_v2_only.js ..\plexus-frontend
const fs = require('fs');
const path = require('path');
const repo = process.argv[2];
if (!repo || !fs.existsSync(path.join(repo, 'lib/blockchain/v2'))) {
  console.error('Usage : node apply_v2_only.js <dossier plexus-frontend clone>');
  process.exit(1);
}
const BACKUP = '_backup_v2_only';
function copy(rel) {
  if (fs.existsSync(rel)) {
    const b = path.join(BACKUP, rel);
    fs.mkdirSync(path.dirname(b), { recursive: true });
    fs.copyFileSync(rel, b);
  }
  fs.mkdirSync(path.dirname(rel), { recursive: true });
  fs.copyFileSync(path.join(repo, rel), rel);
}
function copyDir(rel) {
  for (const e of fs.readdirSync(path.join(repo, rel), { withFileTypes: true })) {
    const r = rel + '/' + e.name;
    e.isDirectory() ? copyDir(r) : copy(r);
  }
}
['lib/blockchain/v2', 'lib/dev', 'test/blockchain', 'test/fixtures'].forEach(copyDir);
copy('lib/main_wallet_test.dart');
copy('lib/presentation/screens/order_detail_screen.dart');
copy('test/widget_test.dart');

// Garder l'ancien import (pas de material_ui sur Flutter 3.41)
const f = 'lib/presentation/screens/order_detail_screen.dart';
let s = fs.readFileSync(f, 'utf8');
s = s.replace('package:material_ui/material_ui.dart', 'package:flutter/material.dart');
fs.writeFileSync(f, s);
console.log('Termine. Sauvegarde dans ./' + BACKUP);