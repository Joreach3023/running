#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/ios/App/App/public"
INDEX="$APP_DIR/index.html"

SOURCE_STORAGE_JS="$ROOT_DIR/runpacer-storage.js"
DEST_STORAGE_JS="$APP_DIR/runpacer-storage.js"
SOURCE_HISTORY_JS="$ROOT_DIR/runpacer-history-bootstrap.js"
DEST_HISTORY_JS="$APP_DIR/runpacer-history-bootstrap.js"
SOURCE_TRAINING_STORAGE_JS="$ROOT_DIR/runpacer-training-storage.js"
DEST_TRAINING_STORAGE_JS="$APP_DIR/runpacer-training-storage.js"
SOURCE_TRAINING_BOOTSTRAP_JS="$ROOT_DIR/runpacer-training-bootstrap.js"
DEST_TRAINING_BOOTSTRAP_JS="$APP_DIR/runpacer-training-bootstrap.js"

STORAGE_MARKER='<script src="runpacer-storage.js"></script>'
HISTORY_MARKER='<script src="runpacer-history-bootstrap.js"></script>'
TRAINING_STORAGE_MARKER='<script src="runpacer-training-storage.js"></script>'
TRAINING_BOOTSTRAP_MARKER='<script src="runpacer-training-bootstrap.js"></script>'

if [ ! -d "$APP_DIR" ]; then
  echo "ERREUR: dossier Capacitor introuvable: $APP_DIR"
  exit 1
fi

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

for source in \
  "$SOURCE_STORAGE_JS" \
  "$SOURCE_HISTORY_JS" \
  "$SOURCE_TRAINING_STORAGE_JS" \
  "$SOURCE_TRAINING_BOOTSTRAP_JS"; do
  if [ ! -f "$source" ]; then
    echo "ERREUR: fichier SwiftData introuvable: $source"
    exit 1
  fi
done

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$APP_DIR/.backup_swiftdata_$STAMP"
mkdir -p "$BACKUP_DIR"
cp "$INDEX" "$BACKUP_DIR/index.html.bak"
[ -f "$DEST_STORAGE_JS" ] && cp "$DEST_STORAGE_JS" "$BACKUP_DIR/runpacer-storage.js.bak"
[ -f "$DEST_HISTORY_JS" ] && cp "$DEST_HISTORY_JS" "$BACKUP_DIR/runpacer-history-bootstrap.js.bak"
[ -f "$DEST_TRAINING_STORAGE_JS" ] && cp "$DEST_TRAINING_STORAGE_JS" "$BACKUP_DIR/runpacer-training-storage.js.bak"
[ -f "$DEST_TRAINING_BOOTSTRAP_JS" ] && cp "$DEST_TRAINING_BOOTSTRAP_JS" "$BACKUP_DIR/runpacer-training-bootstrap.js.bak"

cp "$SOURCE_STORAGE_JS" "$DEST_STORAGE_JS"
cp "$SOURCE_HISTORY_JS" "$DEST_HISTORY_JS"
cp "$SOURCE_TRAINING_STORAGE_JS" "$DEST_TRAINING_STORAGE_JS"
cp "$SOURCE_TRAINING_BOOTSTRAP_JS" "$DEST_TRAINING_BOOTSTRAP_JS"

python3 - "$INDEX" \
  "$STORAGE_MARKER" \
  "$HISTORY_MARKER" \
  "$TRAINING_STORAGE_MARKER" \
  "$TRAINING_BOOTSTRAP_MARKER" <<'PY'
import pathlib
import sys

index_path = pathlib.Path(sys.argv[1])
markers = [
    ('RunPacer iOS personal storage: SwiftData bridge', sys.argv[2]),
    ('RunPacer iOS history: SwiftData-first bootstrap', sys.argv[3]),
    ('RunPacer iOS training plan: SwiftData bridge', sys.argv[4]),
    ('RunPacer iOS training plan: SwiftData-first bootstrap', sys.argv[5]),
]

text = index_path.read_text(encoding='utf-8')
missing = [(comment, marker) for comment, marker in markers if marker not in text]

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
echo " RunPacer SwiftData personnel installé"
echo "============================================================"
echo "Backup  : $BACKUP_DIR"
echo "Storage : $DEST_STORAGE_JS"
echo "History : $DEST_HISTORY_JS"
echo "Plan    : $DEST_TRAINING_STORAGE_JS"
echo "Plan UI : $DEST_TRAINING_BOOTSTRAP_JS"
echo ""
echo "Au prochain build, RunPacer va :"
echo " - conserver les courses et leurs payloads complets dans SwiftData"
echo " - lire l'historique affiché depuis SwiftData en priorité"
echo " - importer le plan d'entraînement dans une entité SwiftData dédiée"
echo " - lire ensuite le plan depuis SwiftData en priorité"
echo " - conserver localStorage comme fallback temporaire"
echo " - laisser Supabase/social fonctionner comme avant"
echo ""
echo "Tu peux maintenant rebâtir l'app dans Xcode."
