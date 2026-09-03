#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

python3 - "$INDEX" <<'PY'
import pathlib, re, shutil, subprocess, sys, tempfile
from datetime import datetime

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = 'data-like-run="${r.id}"'
pos = text.find(marker)
if pos < 0:
    raise SystemExit('ERREUR: bloc du feed social phase 3 introuvable.')

# Trouver le <script> qui contient le feed.
script_open = text.rfind('<script', 0, pos)
script_body = text.find('>', script_open) + 1
script_close = text.find('</script>', pos)
if script_open < 0 or script_body <= 0 or script_close < 0:
    raise SystemExit('ERREUR: bloc <script> du feed introuvable.')

script = text[script_body:script_close]
local_pos = pos - script_body

# Cibler seulement la fermeture fautive située juste après le .join('').
window_start = max(0, local_pos - 2500)
window_end = min(len(script), local_pos + 2500)
window = script[window_start:window_end]

pattern = re.compile(r"(\}\)\.join\(''\);\s*)\}\)\(\);", re.M)
m = pattern.search(window)
if not m:
    # Variante avec indentation/espaces différents.
    pattern = re.compile(r"(\}\)\.join\(''\);\s*)\}\s*\)\s*\(\s*\)\s*;", re.M)
    m = pattern.search(window)
if not m:
    raise SystemExit('ERREUR: fermeture fautive du feed non reconnue; aucune modification faite.')

abs_start = script_body + window_start + m.start()
abs_end = script_body + window_start + m.end()
original_fragment = text[abs_start:abs_end]

candidates = [
    m.group(1) + '}',
    m.group(1) + '};',
    m.group(1),
]


def check_candidate(candidate_text: str):
    cand_script = candidate_text[script_body:script_close + (len(candidate_text)-len(text))]
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(cand_script)
        tmp = f.name
    try:
        p = subprocess.run(['node','--check',tmp], capture_output=True, text=True)
        return p.returncode == 0, (p.stderr or p.stdout).strip()
    finally:
        pathlib.Path(tmp).unlink(missing_ok=True)

chosen = None
chosen_label = None
for idx, replacement in enumerate(candidates, start=1):
    candidate = text[:abs_start] + replacement + text[abs_end:]
    ok, detail = check_candidate(candidate)
    if ok:
        chosen = candidate
        chosen_label = idx
        break

if chosen is None:
    print('ERREUR: aucune réparation candidate ne passe node --check.')
    print('Fragment actuel:')
    print(original_fragment)
    raise SystemExit(2)

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = path.with_name(f'index.html.backup_js_feed_fix_{stamp}')
shutil.copy2(path, backup)
path.write_text(chosen, encoding='utf-8')

# Validation finale du même bloc après écriture.
new_text = path.read_text(encoding='utf-8')
new_script_close = new_text.find('</script>', pos)
new_script = new_text[script_body:new_script_close]
with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as f:
    f.write(new_script)
    tmp = f.name
try:
    p = subprocess.run(['node','--check',tmp], capture_output=True, text=True)
    if p.returncode != 0:
        shutil.copy2(backup, path)
        print((p.stderr or p.stdout).strip())
        raise SystemExit('ERREUR: validation finale échouée; backup restauré automatiquement.')
finally:
    pathlib.Path(tmp).unlink(missing_ok=True)

print('Réparation JavaScript appliquée.')
print('- feed-social-closing-fixed')
print(f'- candidate-syntax-valid-{chosen_label}')
print('- node-check: OK')
print('Backup:', backup)
print('Aucune donnée utilisateur n’a été supprimée.')
PY
