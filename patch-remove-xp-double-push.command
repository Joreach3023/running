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
replacement = "                        // addXP() synchronise déjà l'XP avec Supabase.\n"
startup_call = "        RunpacerXP.pushToSupabase()\n"

target_count = text.count(target)
replacement_count = text.count(replacement)

if target_count == 0 and replacement_count >= 2:
    print("Patch XP double-push déjà appliqué.")
    sys.exit(0)

if target_count != 2:
    raise SystemExit(
        f"ERREUR: 2 appels post-addXP attendus, trouvé {target_count}. Aucun changement appliqué."
    )

if startup_call not in text:
    raise SystemExit(
        "ERREUR: appel pushToSupabase() de démarrage introuvable. Aucun changement appliqué."
    )

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = index_path.with_name(f"index.html.backup_xp_double_push_{stamp}")
shutil.copy2(index_path, backup)

text = text.replace(target, replacement)
index_path.write_text(text, encoding="utf-8")

print("Patch XP double-push appliqué.")
print("- 2 pushes redondants retirés: course normale + Boss Run")
print("- addXP() garde sa synchronisation Supabase")
print("- Le pushToSupabase() de démarrage est conservé")
print("- Aucun calcul XP modifié")
print("- Aucune donnée Supabase modifiée par ce script")
print("- Backup:", backup)
PY
