#!/usr/bin/env bash
# Verifies that src/ matches the files embedded in install.sh (install.sh is the source of truth).
set -euo pipefail
cd "$(dirname "$0")/.."
extract(){ sed -n "/^cat > \"\$DEST\/$1\" <<'PHP'$/,/^PHP$/p" install.sh | sed '1d;$d'; }
rc=0
diff -u <(extract config.php) src/config.php.tpl || rc=1
diff -u <(extract layout.php) src/layout.php     || rc=1
diff -u <(extract index.php)  src/index.php      || rc=1
[ $rc -eq 0 ] && echo "src/ is in sync with install.sh" || { echo "src/ differs from install.sh — regenerate with: scripts/extract-src.sh"; exit 1; }
