#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"
TARGET_LINE="${1:-11133}"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

echo
echo "RunPacer — diagnostic JavaScript"
echo "Fichier: $INDEX"
echo "Ligne signalée par WebKit: $TARGET_LINE"
echo

echo "===== CONTEXTE AUTOUR DE LA LIGNE $TARGET_LINE ====="
START=$((TARGET_LINE-18)); [ "$START" -lt 1 ] && START=1
END=$((TARGET_LINE+18))
nl -ba "$INDEX" | sed -n "${START},${END}p"
echo

echo "===== MARQUEURS DE PATCH À PROXIMITÉ ====="
python3 - "$INDEX" "$TARGET_LINE" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1])
target=int(sys.argv[2])
lines=p.read_text(encoding='utf-8').splitlines()
lo=max(0,target-120)
hi=min(len(lines),target+120)
markers=('RunPacer social','Boss Run','phase3','rpLoadBossInvites','rpToggleRunLike','rpAddRunComment','rpNotifySocialEvent','rpInviteToBossRun')
found=False
for i in range(lo,hi):
    if any(m in lines[i] for m in markers):
        print(f'{i+1}: {lines[i][:220]}')
        found=True
if not found:
    print('(aucun marqueur récent trouvé dans ±120 lignes)')
PY

echo

echo "===== TEST DE SYNTAXE DU <script> QUI CONTIENT LA LIGNE ====="
python3 - "$INDEX" "$TARGET_LINE" <<'PY'
import pathlib, re, subprocess, sys, tempfile
p=pathlib.Path(sys.argv[1])
target=int(sys.argv[2])
text=p.read_text(encoding='utf-8')
lines=text.splitlines(True)
offsets=[]; n=0
for line in lines:
    offsets.append(n); n+=len(line)
pos=offsets[min(max(target-1,0),len(offsets)-1)]
starts=[m for m in re.finditer(r'<script(?:\s[^>]*)?>', text, re.I) if m.start() <= pos]
if not starts:
    print('Aucun <script> avant la ligne cible.')
    raise SystemExit(0)
start=starts[-1]
end=re.search(r'</script\s*>', text[start.end():], re.I)
if not end:
    print('Aucun </script> trouvé après ce bloc.')
    raise SystemExit(0)
body_start=start.end()
body_end=start.end()+end.start()
if not (body_start <= pos <= body_end):
    print('La ligne cible n’est pas dans un bloc <script>.')
    raise SystemExit(0)
body=text[body_start:body_end]
start_line=text[:body_start].count('\n')+1
print(f'Bloc <script> commence vers la ligne HTML {start_line}.')
with tempfile.NamedTemporaryFile('w',suffix='.js',delete=False,encoding='utf-8') as f:
    f.write(body)
    tmp=f.name
try:
    r=subprocess.run(['node','--check',tmp],capture_output=True,text=True)
except FileNotFoundError:
    print('Node.js introuvable; contexte ci-dessus suffira pour corriger.')
    raise SystemExit(0)
print('node --check exit:',r.returncode)
if r.stdout.strip(): print(r.stdout.strip())
if r.stderr.strip(): print(r.stderr.strip())
print(f'Pour convertir une ligne JS du diagnostic en ligne HTML, ajoute environ {start_line-1}.')
PY

echo
echo "===== FIN DU DIAGNOSTIC ====="
echo "Copie toute cette sortie dans ChatGPT. Aucune donnée n'a été modifiée."
