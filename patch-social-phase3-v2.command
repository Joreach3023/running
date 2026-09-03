#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"
PHASE3="$ROOT_DIR/patch-social-phase3.command"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi
if [ ! -f "$PHASE3" ]; then
  echo "ERREUR: patch-social-phase3.command introuvable. Fais git pull."
  exit 1
fi

python3 - "$INDEX" <<'PY'
import pathlib, shutil, sys
from datetime import datetime

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
changes=[]

# Phase 3 replaces this function with the complete robust implementation.
# Some local Capacitor/Xcode rebuilds can restore an older index.html that no
# longer contains the function injected by the previous Boss Run patch.
if 'window.rpLoadBossInvites' not in text:
    stamp=datetime.now().strftime('%Y%m%d_%H%M%S')
    backup=path.with_name(f'index.html.backup_phase3_prereq_{stamp}')
    shutil.copy2(path,backup)
    stub='''\n<script>\n/* RunPacer phase3 prerequisite hook */\nwindow.rpLoadBossInvites = async function(){};\n</script>\n'''
    if '</body>' in text:
        text=text.replace('</body>',stub+'\n</body>',1)
    else:
        text += stub
    path.write_text(text,encoding='utf-8')
    changes.append('boss-invite-inbox-hook-restored')
    print('Pré-requis phase 3 réparé.')
    print('-',changes[0])
    print('Backup:',backup)
else:
    print('Pré-requis phase 3 déjà présent.')
PY

echo "Lancement de patch-social-phase3.command…"
bash "$PHASE3"
