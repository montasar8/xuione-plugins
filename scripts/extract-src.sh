#!/usr/bin/env bash
# Regenerates src/ from the files embedded in install.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
extract(){ sed -n "/^cat > \"\$DEST\/$1\" <<'PHP'$/,/^PHP$/p" install.sh | sed '1d;$d'; }
extract config.php > src/config.php.tpl
extract layout.php > src/layout.php
extract index.php  > src/index.php
echo "src/ regenerated from install.sh"
