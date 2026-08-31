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

target = "                        RunpacerXP.pushToSupabase?.();\n"
marker = "                        // addXP() synchronise déjà l'XP avec Supabase.\n"

if marker in text and target not in text:
    print("Patch XP double-push déjà appliqué.")
    sys.exit(0)

count = text.count(target)
if count != 1:
    raise SystemExit(
        f"ERREUR: appel RunpacerXP.pushToSupabase attendu 1 fois dans ce contexte, trouvé {count} fois. Aucun changement appliqué."
    )

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = index_path.with_name(f"index.html.backup_xp_double_push_{stamp}")
shutil.copy2(index_path, backup)

text = text.replace(target, marker, 1)
index_path.write_text(text, encoding="utf-8")

print("Patch XP double-push appliqué.")
print("- addXP() garde sa synchronisation Supabase")
print("- Le second pushToSupabase() après la course a été retiré")
print("- Aucun calcul XP modifié")
print("- Aucune donnée Supabase modifiée par ce script")
print("- Backup:", backup)
PY
