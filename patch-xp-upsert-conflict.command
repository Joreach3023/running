#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
XP="$ROOT_DIR/ios/App/App/public/xp.js"

if [ ! -f "$XP" ]; then
  echo "ERREUR: xp.js introuvable: $XP"
  exit 1
fi

python3 - "$XP" <<'PY'
import pathlib
import shutil
import sys
from datetime import datetime

xp_path = pathlib.Path(sys.argv[1])
text = xp_path.read_text(encoding="utf-8")

old = "fetch(`${SUPABASE_URL}/rest/v1/user_xp`, {"
new = "fetch(`${SUPABASE_URL}/rest/v1/user_xp?on_conflict=user_key`, {"

if new in text:
    print("Patch XP déjà appliqué: on_conflict=user_key est présent.")
    sys.exit(0)

count = text.count(old)
if count != 1:
    raise SystemExit(f"ERREUR: appel _sbUpsert attendu 1 fois, trouvé {count} fois. Aucun changement appliqué.")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = xp_path.with_name(f"xp.js.backup_upsert_{stamp}")
shutil.copy2(xp_path, backup)

text = text.replace(old, new, 1)
xp_path.write_text(text, encoding="utf-8")

print("Patch XP Supabase appliqué.")
print("- Upsert désormais basé sur UNIQUE(user_key)")
print("- Aucun calcul XP modifié")
print("- Aucune donnée Supabase supprimée")
print("- Backup:", backup)
PY
