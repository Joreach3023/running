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

needle = "            }).join('');\n        })();\n</script>"
replacement = "            }).join('');\n        }\n</script>"

if needle not in text:
    # Tolérer des espaces/tabs différents, mais rester très ciblé sur le feed social.
    pattern = re.compile(r"(\s*\}\)\.join\(''\);\s*)\}\)\(\);(\s*</script>)")
    matches = list(pattern.finditer(text))
    # Garder seulement le match proche du bouton data-like-run.
    target = None
    like_pos = text.find('data-like-run="${r.id}"')
    for m in matches:
        if like_pos >= 0 and 0 < m.start() - like_pos < 4000:
            target = m
            break
    if not target:
        raise SystemExit('ERREUR: fermeture fautive près du feed social introuvable; aucune modification faite.')
    candidate = text[:target.start()] + target.group(1) + '}' + target.group(2) + text[target.end():]
else:
    candidate = text.replace(needle, replacement, 1)

# Vérifier tous les blocs <script> inline avant d'écrire.
script_re = re.compile(r'<script(?:\s[^>]*)?>(.*?)</script>', re.S | re.I)
invalid=[]
for idx, m in enumerate(script_re.finditer(candidate), start=1):
    body = m.group(1)
    if not body.strip():
        continue
    # Les scripts de type JSON ne sont pas du JS exécutable.
    tag = candidate[m.start():candidate.find('>', m.start())+1].lower()
    if 'application/json' in tag or 'type="importmap"' in tag or "type='importmap'" in tag:
        continue
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(body)
        tmp=f.name
    try:
        p=subprocess.run(['node','--check',tmp],capture_output=True,text=True)
        if p.returncode != 0:
            line_no = candidate.count('\n',0,m.start())+1
            invalid.append((idx,line_no,(p.stderr or p.stdout).strip()))
    finally:
        pathlib.Path(tmp).unlink(missing_ok=True)

if invalid:
    print('ERREUR: la correction proposée laisse du JavaScript invalide. Aucun fichier modifié.')
    for idx,line_no,detail in invalid:
        print(f'Bloc #{idx} vers ligne HTML {line_no}:')
        print(detail)
    raise SystemExit(2)

stamp=datetime.now().strftime('%Y%m%d_%H%M%S')
backup=path.with_name(f'index.html.backup_line11133_{stamp}')
shutil.copy2(path,backup)
path.write_text(candidate,encoding='utf-8')

# Vérification ciblée de la ligne désormais corrigée.
new_lines=candidate.splitlines()
for n in range(11129, min(11136,len(new_lines))+1):
    print(f'{n:6d}\t{new_lines[n-1]}')

print('\nRéparation appliquée.')
print('- ligne 11133: fermeture rpLoadFeed corrigée')
print('- tous les blocs JavaScript: node --check OK')
print('Backup:',backup)
print('Aucune donnée utilisateur n\'a été supprimée.')
PY
