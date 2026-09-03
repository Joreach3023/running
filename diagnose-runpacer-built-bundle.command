#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$ROOT_DIR/ios/App/App/public/index.html"

if [ ! -f "$SOURCE" ]; then
  echo "ERREUR: source index.html introuvable: $SOURCE"
  exit 1
fi

check_html() {
  local label="$1"
  local file="$2"
  echo
  echo "===== $label ====="
  echo "Fichier: $file"
  echo "SHA256: $(shasum -a 256 "$file" | awk '{print $1}')"
  echo "Lignes: $(wc -l < "$file" | tr -d ' ')"
  echo "Ligne 11133:"
  sed -n '11130,11136p' "$file" | nl -ba -v11130

  python3 - "$file" <<'PY'
import pathlib, re, subprocess, sys, tempfile
p=pathlib.Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
blocks=[]
for m in re.finditer(r'<script(?:\s[^>]*)?>(.*?)</script>', text, re.S|re.I):
    body=m.group(1)
    if body.strip():
        blocks.append((text.count('\n',0,m.start())+1,body))

failed=[]
for i,(line,body) in enumerate(blocks,1):
    with tempfile.NamedTemporaryFile('w',suffix='.js',delete=False,encoding='utf-8') as f:
        f.write(body); name=f.name
    try:
        r=subprocess.run(['node','--check',name],capture_output=True,text=True)
    finally:
        pathlib.Path(name).unlink(missing_ok=True)
    if r.returncode:
        failed.append((i,line,(r.stderr or r.stdout).strip()))

if not failed:
    print('JS CHECK: OK — tous les scripts inline passent node --check')
else:
    print(f'JS CHECK: ECHEC — {len(failed)} bloc(s) invalide(s)')
    for i,line,detail in failed[:4]:
        print(f'Bloc #{i}, commence ligne HTML ~{line}')
        print(detail)
PY
}

check_html "SOURCE LOCAL" "$SOURCE"

# Trouver la copie la plus récente construite par Xcode.
BUILT=""
DD="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DD" ]; then
  BUILT="$(find "$DD" -type f -path '*/Build/Products/*/RunPacer.app/public/index.html' -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -n 1 || true)"
  if [ -z "$BUILT" ]; then
    BUILT="$(find "$DD" -type f -path '*/Build/Products/*/RunPacer.app/index.html' -print0 2>/dev/null \
      | xargs -0 ls -t 2>/dev/null | head -n 1 || true)"
  fi
fi

if [ -n "$BUILT" ] && [ -f "$BUILT" ]; then
  check_html "COPIE BUILT XCODE" "$BUILT"
  SRC_SHA="$(shasum -a 256 "$SOURCE" | awk '{print $1}')"
  BUILT_SHA="$(shasum -a 256 "$BUILT" | awk '{print $1}')"
  echo
  if [ "$SRC_SHA" = "$BUILT_SHA" ]; then
    echo "COMPARAISON: IDENTIQUES ✅"
  else
    echo "COMPARAISON: DIFFERENTS ⚠️"
    echo "Xcode n'a pas embarqué la même copie que ios/App/App/public/index.html."
  fi
else
  echo
  echo "Aucune copie RunPacer.app/index.html trouvée dans DerivedData."
  echo "Fais un Build dans Xcode puis relance ce diagnostic."
fi

echo
echo "Aucune donnée ni aucun fichier n'a été modifié."
