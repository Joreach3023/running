#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/ios/App/App/public"
INDEX="$APP_DIR/index.html"
SOURCE_JS="$ROOT_DIR/runpacer-storage.js"
DEST_JS="$APP_DIR/runpacer-storage.js"
MARKER='<script src="runpacer-storage.js"></script>'

if [ ! -d "$APP_DIR" ]; then
  echo "ERREUR: dossier Capacitor introuvable: $APP_DIR"
  exit 1
fi

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

if [ ! -f "$SOURCE_JS" ]; then
  echo "ERREUR: runpacer-storage.js introuvable: $SOURCE_JS"
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$APP_DIR/.backup_swiftdata_$STAMP"
mkdir -p "$BACKUP_DIR"
cp "$INDEX" "$BACKUP_DIR/index.html.bak"
[ -f "$DEST_JS" ] && cp "$DEST_JS" "$BACKUP_DIR/runpacer-storage.js.bak"

cp "$SOURCE_JS" "$DEST_JS"

python3 - "$INDEX" "$MARKER" <<'PY'
import pathlib
import sys

index_path = pathlib.Path(sys.argv[1])
marker = sys.argv[2]
text = index_path.read_text(encoding='utf-8')

if marker in text:
    print('runpacer-storage.js déjà chargé dans index.html')
    raise SystemExit(0)

insertion = '\n    <!-- RunPacer iOS personal storage: SwiftData mirror -->\n    ' + marker + '\n'

if '</body>' in text:
    text = text.replace('</body>', insertion + '</body>', 1)
else:
    text += insertion

index_path.write_text(text, encoding='utf-8')
print('runpacer-storage.js ajouté à index.html')
PY

echo ""
echo "============================================================"
echo " RunPacer SwiftData sync installé"
echo "============================================================"
echo "Backup : $BACKUP_DIR"
echo "JS     : $DEST_JS"
echo ""
echo "Au prochain build, RunPacer va :"
echo " - importer automatiquement l'historique local dans SwiftData"
echo " - sauvegarder chaque nouvelle course dans SwiftData"
echo " - sauvegarder le snapshot complet userData + plan d'entraînement"
echo " - laisser Supabase/social fonctionner comme avant"
echo ""
echo "Tu peux maintenant rebâtir l'app dans Xcode."
