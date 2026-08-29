#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/ios/App/App/public"
INDEX="$APP_DIR/index.html"
SOURCE_STORAGE_JS="$ROOT_DIR/runpacer-storage.js"
DEST_STORAGE_JS="$APP_DIR/runpacer-storage.js"
SOURCE_HISTORY_JS="$ROOT_DIR/runpacer-history-bootstrap.js"
DEST_HISTORY_JS="$APP_DIR/runpacer-history-bootstrap.js"
STORAGE_MARKER='<script src="runpacer-storage.js"></script>'
HISTORY_MARKER='<script src="runpacer-history-bootstrap.js"></script>'

if [ ! -d "$APP_DIR" ]; then
  echo "ERREUR: dossier Capacitor introuvable: $APP_DIR"
  exit 1
fi

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

if [ ! -f "$SOURCE_STORAGE_JS" ]; then
  echo "ERREUR: runpacer-storage.js introuvable: $SOURCE_STORAGE_JS"
  exit 1
fi

if [ ! -f "$SOURCE_HISTORY_JS" ]; then
  echo "ERREUR: runpacer-history-bootstrap.js introuvable: $SOURCE_HISTORY_JS"
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$APP_DIR/.backup_swiftdata_$STAMP"
mkdir -p "$BACKUP_DIR"
cp "$INDEX" "$BACKUP_DIR/index.html.bak"
[ -f "$DEST_STORAGE_JS" ] && cp "$DEST_STORAGE_JS" "$BACKUP_DIR/runpacer-storage.js.bak"
[ -f "$DEST_HISTORY_JS" ] && cp "$DEST_HISTORY_JS" "$BACKUP_DIR/runpacer-history-bootstrap.js.bak"

cp "$SOURCE_STORAGE_JS" "$DEST_STORAGE_JS"
cp "$SOURCE_HISTORY_JS" "$DEST_HISTORY_JS"

python3 - "$INDEX" "$STORAGE_MARKER" "$HISTORY_MARKER" <<'PY'
import pathlib
import sys

index_path = pathlib.Path(sys.argv[1])
storage_marker = sys.argv[2]
history_marker = sys.argv[3]
text = index_path.read_text(encoding='utf-8')

missing = []
if storage_marker not in text:
    missing.append(('RunPacer iOS personal storage: SwiftData bridge', storage_marker))
if history_marker not in text:
    missing.append(('RunPacer iOS history: SwiftData-first bootstrap', history_marker))

if not missing:
    print('Scripts SwiftData déjà chargés dans index.html')
    raise SystemExit(0)

insertion = ''
for comment, marker in missing:
    insertion += f'\n    <!-- {comment} -->\n    {marker}\n'

if '</body>' in text:
    text = text.replace('</body>', insertion + '</body>', 1)
else:
    text += insertion

index_path.write_text(text, encoding='utf-8')
for _, marker in missing:
    print(marker, 'ajouté à index.html')
PY

echo ""
echo "============================================================"
echo " RunPacer SwiftData sync + historique installés"
echo "============================================================"
echo "Backup : $BACKUP_DIR"
echo "Storage: $DEST_STORAGE_JS"
echo "History: $DEST_HISTORY_JS"
echo ""
echo "Au prochain build, RunPacer va :"
echo " - importer/synchroniser l'historique personnel dans SwiftData"
echo " - lire l'historique affiché depuis SwiftData en priorité"
echo " - rattacher GPS, splits et détails depuis le snapshot SwiftData"
echo " - conserver localStorage comme fallback temporaire"
echo " - laisser Supabase/social fonctionner comme avant"
echo ""
echo "Tu peux maintenant rebâtir l'app dans Xcode."
