#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PBXPROJ="$ROOT_DIR/ios/App/App.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
  echo "ERREUR: project.pbxproj introuvable: $PBXPROJ"
  exit 1
fi

python3 - "$PBXPROJ" <<'PY'
import pathlib
import shutil
import sys
from datetime import datetime

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "IPHONEOS_DEPLOYMENT_TARGET = 14.0;"
new = "IPHONEOS_DEPLOYMENT_TARGET = 17.0;"

old_count = text.count(old)
new_count = text.count(new)

if old_count == 0 and new_count >= 4:
    print("Deployment target iOS 17 déjà appliqué.")
    raise SystemExit(0)

if old_count != 4:
    raise SystemExit(
        f"ERREUR: 4 réglages iOS 14.0 attendus, trouvé {old_count}. Aucun changement appliqué."
    )

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = path.with_name(f"project.pbxproj.backup_ios17_{stamp}")
shutil.copy2(path, backup)

text = text.replace(old, new)
path.write_text(text, encoding="utf-8")

print("Deployment target mis à jour vers iOS 17.0.")
print("- Projet Debug: 17.0")
print("- Projet Release: 17.0")
print("- Target RunPacer Debug: 17.0")
print("- Target RunPacer Release: 17.0")
print("- Aucun autre réglage modifié")
print("- Backup:", backup)
PY
