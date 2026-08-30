#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

python3 - "$INDEX" <<'PY'
import pathlib
import shutil
import sys
from datetime import datetime

index_path = pathlib.Path(sys.argv[1])
text = index_path.read_text(encoding='utf-8')

old = "loadTextureWithFallback(TEX_CLOUDS, makeCloudFallback),"
new = "Promise.resolve(makeCloudFallback()), // Nuages locaux: évite le 404/CORS unpkg"

if new in text:
    print('Nuages du globe déjà configurés en local.')
    raise SystemExit(0)

count = text.count(old)
if count != 1:
    raise SystemExit(f'ERREUR: appel TEX_CLOUDS attendu 1 fois, trouvé {count} fois. Aucun changement appliqué.')

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = index_path.with_name(f'index.html.before_local_clouds_{stamp}.bak')
shutil.copy2(index_path, backup)

text = text.replace(old, new, 1)
index_path.write_text(text, encoding='utf-8')

print('Patch globe appliqué: nuages procéduraux locaux utilisés directement.')
print('La requête distante clouds.png ne sera plus effectuée.')
print('Backup :', backup)
PY
