#!/usr/bin/env bash
# Run once from the Flutter project root (where pubspec.yaml is).
# Every screen/provider that used `package:http/http.dart as http` now uses the version that
# sends the login token. Nothing else in those files changes.
set -euo pipefail
OLD="import 'package:http/http.dart' as http;"
NEW="import 'package:plexus/core/http_auth.dart' as http;"
grep -rl --include=*.dart "$OLD" lib | grep -v 'lib/core/http_auth.dart' | while read -r f; do
  sed -i "s#$OLD#$NEW#" "$f"
  echo "updated $f"
done
