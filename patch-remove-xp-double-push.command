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
text = index_path.read_text(encoding="utf-8")

old_block = """                        if (typeof renderXPWidgets === 'function') renderXPWidgets();
                        RunpacerXP.pushToSupabase?.();
"""
new_block = """                        if (typeof renderXPWidgets === 'function') renderXPWidgets();
                        // addXP() synchronise déjà l'XP avec Supabase.
"""

if new_block in text and old_block not in text:
    print("Patch XP double-push déjà appliqué.")
    sys.exit(0)

count = text.count(old_block)
if count != 1:
    raise SystemExit(
        f"ERREUR: bloc XP de fin de course attendu 1 fois, trouvé {count} fois. Aucun changement appliqué."
    )

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = index_path.with_name(f"index.html.backup_xp_double_push_{stamp}")
shutil.copy2(index_path, backup)

text = text.replace(old_block, new_block, 1)
index_path.write_text(text, encoding="utf-8")

print("Patch XP double-push appliqué.")
print("- addXP() garde sa synchronisation Supabase")
print("- Seul le pushToSupabase() juste après renderXPWidgets() a été retiré")
print("- Les autres usages de pushToSupabase() restent intacts")
print("- Aucun calcul XP modifié")
print("- Aucune donnée Supabase modifiée par ce script")
print("- Backup:", backup)
PY
