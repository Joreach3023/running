#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFICATIONS="$ROOT_DIR/ios/App/App/public/notifications.js"

if [ ! -f "$NOTIFICATIONS" ]; then
  echo "ERREUR: notifications.js introuvable: $NOTIFICATIONS"
  exit 1
fi

python3 - "$NOTIFICATIONS" <<'PY'
import pathlib
import shutil
import sys
from datetime import datetime

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')

marker = '// RunPacer temporary APNs auto-registration guard'
old_flag = 'autoRegistrationEnabled: false,'
old_reason = "reason: 'apns-provisioning-temporarily-disabled'"
new_flag = 'autoRegistrationEnabled: true,'
new_reason = "reason: 'apns-provisioning-active'"

if marker not in text:
    raise SystemExit('ERREUR: garde Push temporaire introuvable dans notifications.js. Aucun changement appliqué.')

if new_flag in text and new_reason in text:
    print('Push automatique déjà réactivé.')
    raise SystemExit(0)

if text.count(old_flag) != 1 or text.count(old_reason) != 1:
    raise SystemExit(
        'ERREUR: état Push temporaire inattendu. Aucun changement appliqué.\n'
        f'- autoRegistrationEnabled:false trouvé {text.count(old_flag)} fois\n'
        f'- raison temporaire trouvée {text.count(old_reason)} fois'
    )

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = path.with_name(f'notifications.js.before_enable_auto_push_{stamp}.bak')
shutil.copy2(path, backup)

text = text.replace(old_flag, new_flag, 1)
text = text.replace(old_reason, new_reason, 1)
path.write_text(text, encoding='utf-8')

print('Push automatique réactivé.')
print('- rpInitPush() sera lancé automatiquement au démarrage')
print('- provisioning APNs attendu: actif')
print('- aucun token existant supprimé')
print('- aucune donnée Supabase modifiée par ce script')
print('Backup :', backup)
PY
