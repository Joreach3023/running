#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_DIR="$ROOT_DIR/ios/App/App/public"
INDEX="$PUBLIC_DIR/index.html"
SW="$PUBLIC_DIR/service-worker.js"
VENDOR_DIR="$PUBLIC_DIR/vendor"
CHART_LOCAL="$VENDOR_DIR/chart.js"
CHART_CDN="https://cdn.jsdelivr.net/npm/chart.js"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

mkdir -p "$VENDOR_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$PUBLIC_DIR/.backup_chartjs_local_$STAMP"
mkdir -p "$BACKUP_DIR"
cp "$INDEX" "$BACKUP_DIR/index.html.bak"
[ -f "$SW" ] && cp "$SW" "$BACKUP_DIR/service-worker.js.bak"
[ -f "$CHART_LOCAL" ] && cp "$CHART_LOCAL" "$BACKUP_DIR/chart.js.bak"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Téléchargement de la même ressource Chart.js actuellement utilisée..."
curl -LfsS "$CHART_CDN" -o "$TMP"

if [ ! -s "$TMP" ]; then
  echo "ERREUR: téléchargement Chart.js vide. Aucun changement appliqué."
  exit 1
fi

# Retirer uniquement les directives source map de développement.
python3 - "$TMP" "$CHART_LOCAL" <<'PY'
import pathlib, re, sys
src = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
src = re.sub(r'(?m)^\s*//#\s*sourceMappingURL=.*(?:\n|$)', '', src)
src = re.sub(r'(?m)^\s*/\*#\s*sourceMappingURL=.*?\*/\s*(?:\n|$)', '', src)
pathlib.Path(sys.argv[2]).write_text(src, encoding='utf-8')
PY

python3 - "$INDEX" "$SW" <<'PY'
import pathlib, sys
index_path = pathlib.Path(sys.argv[1])
sw_path = pathlib.Path(sys.argv[2])
old = 'https://cdn.jsdelivr.net/npm/chart.js'
new = 'vendor/chart.js'

index = index_path.read_text(encoding='utf-8')
old_count = index.count(old)
local_count = index.count(new)

if old_count > 1:
    raise SystemExit(f'ERREUR: {old_count} références Chart.js CDN dans index.html; 1 attendue.')
if old_count == 1:
    index = index.replace(old, new, 1)
elif local_count == 0:
    raise SystemExit('ERREUR: référence Chart.js attendue introuvable dans index.html.')

index_path.write_text(index, encoding='utf-8')

if sw_path.exists():
    sw = sw_path.read_text(encoding='utf-8')
    sw = sw.replace(old, new)
    sw_path.write_text(sw, encoding='utf-8')

print('Référence index.html:', 'mise à jour' if old_count == 1 else 'déjà locale')
print('service-worker.js:', 'mis à jour' if sw_path.exists() else 'absent, ignoré')
PY

if grep -qE 'sourceMappingURL=.*chart' "$CHART_LOCAL"; then
  echo "ERREUR: une directive sourceMappingURL Chart.js est encore présente."
  exit 1
fi

if ! grep -q 'vendor/chart.js' "$INDEX"; then
  echo "ERREUR: index.html ne pointe pas vers vendor/chart.js"
  exit 1
fi

echo "Patch Chart.js local appliqué."
echo "- Fichier local : $CHART_LOCAL"
echo "- Source map de développement retirée"
echo "- Backup : $BACKUP_DIR"
echo "- Aucun code de graphique RunPacer n'a été modifié"
