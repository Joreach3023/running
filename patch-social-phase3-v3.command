#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE3="$ROOT_DIR/patch-social-phase3.command"
TMP="${TMPDIR:-/tmp}/runpacer-social-phase3-runtime.command"

if [ ! -f "$PHASE3" ]; then
  echo "ERREUR: patch-social-phase3.command introuvable. Fais git pull."
  exit 1
fi

python3 - "$PHASE3" "$TMP" <<'PY'
import pathlib, sys

src_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
src = src_path.read_text(encoding='utf-8')

needle = """if not ok:\n    raise SystemExit('ERREUR: fonction rpLoadBossInvites introuvable. Exécute d’abord patch-bossrun-social-invites.command.')\nchanges.append('robust-boss-invite-inbox')"""
replacement = """if not ok:\n    # Certaines anciennes versions de l'inbox contiennent une syntaxe que le\n    # petit analyseur de blocs ci-dessus ne sait pas parcourir. Dans ce cas,\n    # on n'échoue pas: on ajoute la version finale après l'ancienne. Comme\n    # l'assignation est exécutée plus tard dans le document, elle devient la\n    # version active de window.rpLoadBossInvites.\n    override = '\\n<script>\\n' + inbox_fn + '\\n</script>\\n'\n    if '</body>' in text:\n        text = text.replace('</body>', override + '</body>', 1)\n    else:\n        text += override\n    changes.append('robust-boss-invite-inbox-override')\nelse:\n    changes.append('robust-boss-invite-inbox')"""

if needle not in src:
    raise SystemExit('ERREUR: bloc inbox de phase3 non reconnu. Fais git pull puis réessaie.')

src = src.replace(needle, replacement, 1)
out_path.write_text(src, encoding='utf-8')
print('Phase 3 runtime préparée (fallback inbox activé).')
PY

echo "Lancement de la phase 3 robuste…"
bash "$TMP"
rm -f "$TMP"
