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
marker = '// RunPacer safe Wake Lock'

if marker in text:
    print('Wake Lock déjà patché proprement.')
    raise SystemExit(0)

old = """    if ('wakeLock' in navigator) {
        try {
            const wakeLock = await navigator.wakeLock.request('screen');
            wakeLock.addEventListener('release', () => {
                console.log('Wake Lock was released');
            });
            console.log('Wake Lock is active');
        } catch (err) {
            console.error('Wake Lock error:', err);
        }
    }
"""

new = """    // RunPacer safe Wake Lock
    // WKWebView/iOS can expose the API but still reject the request depending on
    // the current permission/activation state. A refusal must never affect a run.
    if ('wakeLock' in navigator && document.visibilityState === 'visible') {
        try {
            window.rpScreenWakeLock = await navigator.wakeLock.request('screen');
            window.rpScreenWakeLock.addEventListener('release', () => {
                window.rpScreenWakeLock = null;
                console.log('[WakeLock] Relâché.');
            });
            console.log('[WakeLock] Actif.');
        } catch (err) {
            window.rpScreenWakeLock = null;
            if (err && err.name === 'NotAllowedError') {
                console.log('[WakeLock] Non disponible dans ce contexte iOS; la course continue normalement.');
            } else {
                console.warn('[WakeLock] Échec inattendu:', err);
            }
        }
    }
"""

if old not in text:
    raise SystemExit('ERREUR: bloc Wake Lock attendu introuvable; aucun changement appliqué.')

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = index_path.with_name(f'index.html.before_wakelock_safe_{stamp}.bak')
shutil.copy2(index_path, backup)
index_path.write_text(text.replace(old, new, 1), encoding='utf-8')

print('Patch Wake Lock appliqué.')
print('- NotAllowedError devient informatif, pas une erreur rouge')
print('- Référence conservée dans window.rpScreenWakeLock')
print('- La course continue même si iOS refuse le Wake Lock')
print('- Backup :', backup)
PY
