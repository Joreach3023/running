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

if marker in text:
    print('Le garde Push automatique est déjà installé.')
    raise SystemExit(0)

needle = 'setTimeout(window.rpInitPush, 1500);'
if needle not in text:
    raise SystemExit('ERREUR: appel automatique rpInitPush introuvable dans notifications.js')

replacement = '''// RunPacer temporary APNs auto-registration guard
  // Keep rpInitPush() intact, but do not auto-register while this build is
  // signed without a Push-capable provisioning profile. Re-enable later by
  // setting this flag to true once Apple Developer/APNs provisioning is active.
  window.RunPacerPushConfig = Object.assign({}, window.RunPacerPushConfig, {
    autoRegistrationEnabled: false,
    reason: 'apns-provisioning-temporarily-disabled'
  });

  if (window.RunPacerPushConfig.autoRegistrationEnabled) {
    setTimeout(window.rpInitPush, 1500);
  } else {
    console.log('[Push] Enregistrement APNs automatique désactivé temporairement.');
  }'''

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = path.with_name(f'notifications.js.before_push_guard_{stamp}.bak')
shutil.copy2(path, backup)
path.write_text(text.replace(needle, replacement, 1), encoding='utf-8')

print('Garde Push automatique appliqué.')
print('- rpInitPush() reste disponible manuellement')
print('- enregistrement APNs automatique: désactivé')
print('- aucun token ni donnée Supabase modifié')
print('Backup :', backup)
PY
