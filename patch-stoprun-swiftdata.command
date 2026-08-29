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
import re
import shutil
import sys
from datetime import datetime

index_path = pathlib.Path(sys.argv[1])
text = index_path.read_text(encoding='utf-8')
marker = '// RunPacer SwiftData-first completed-run save'

if marker in text:
    print('stopRun() est déjà patché en SwiftData-first')
    raise SystemExit(0)

start = text.find('async function stopRun()')
if start == -1:
    raise SystemExit('ERREUR: async function stopRun() introuvable')

end_marker = '// Réafficher le bouton profil'
end = text.find(end_marker, start)
if end == -1:
    raise SystemExit('ERREUR: fin du bloc stopRun() introuvable')

segment = text[start:end]

run_pattern = re.compile(
    r'(?P<indent>[ \t]*)userData\.runs\.unshift\(newRun\);[^\n]*'
)
run_match = run_pattern.search(segment)
if not run_match:
    raise SystemExit('ERREUR: insertion de newRun dans userData.runs introuvable')

indent = run_match.group('indent')
run_replacement = f'''{indent}// RunPacer SwiftData-first completed-run save
{indent}// SwiftData reçoit la course AVANT le stockage local de compatibilité.
{indent}// Si cette écriture échoue, le miroir localStorage reste le filet de sécurité.
{indent}let swiftDataRunSaved = false;
{indent}if (window.RunPacerStorage && typeof window.RunPacerStorage.saveRun === 'function') {{
{indent}    try {{
{indent}        const nativeRunResult = await window.RunPacerStorage.saveRun(newRun);
{indent}        if (nativeRunResult && nativeRunResult.id) {{
{indent}            // Ne pas réutiliser `id`: Supabase garde son propre identifiant.
{indent}            newRun.swiftDataId = nativeRunResult.id;
{indent}        }}
{indent}        swiftDataRunSaved = true;
{indent}        console.log('[SwiftData] Nouvelle course sauvegardée directement:', newRun.swiftDataId || 'ok');
{indent}    }} catch (error) {{
{indent}        console.warn(
{indent}            '[SwiftData] Sauvegarde directe de la course échouée; fallback localStorage conservé:',
{indent}            error && error.message ? error.message : error
{indent}        );
{indent}    }}
{indent}}}
{indent}userData.runs.unshift(newRun); // Compatibilité UI + fallback temporaire'''

segment = segment[:run_match.start()] + run_replacement + segment[run_match.end():]

local_pattern = re.compile(
    r'(?P<indent>[ \t]*)// Sauvegarder dans le stockage local\s*\n'
    r'(?P=indent)localStorage\.setItem\([\'\"]runPacerUserData[\'\"], JSON\.stringify\(userData\)\);'
)
local_match = local_pattern.search(segment)
if not local_match:
    raise SystemExit('ERREUR: sauvegarde locale runPacerUserData introuvable dans stopRun()')

indent = local_match.group('indent')
local_replacement = f'''{indent}// Sauvegarder immédiatement le plan modifié dans son stockage SwiftData dédié.
{indent}// Le plan reste sauvegardé même si aucune séance correspondante n'a été trouvée.
{indent}let swiftDataPlanSaved = false;
{indent}if (window.RunPacerStorage && typeof window.RunPacerStorage.saveTrainingPlan === 'function') {{
{indent}    try {{
{indent}        await window.RunPacerStorage.saveTrainingPlan(userData.trainingPlan || []);
{indent}        swiftDataPlanSaved = true;
{indent}    }} catch (error) {{
{indent}        console.warn(
{indent}            '[SwiftData] Sauvegarde directe du plan échouée; fallback localStorage conservé:',
{indent}            error && error.message ? error.message : error
{indent}        );
{indent}    }}
{indent}}}

{indent}// Stockage local conservé temporairement pour l'ancienne UI et comme
{indent}// filet de sécurité. Le chemin primaire de la course est maintenant SwiftData.
{indent}localStorage.setItem('runPacerUserData', JSON.stringify(userData));'''

segment = segment[:local_match.start()] + local_replacement + segment[local_match.end():]
new_text = text[:start] + segment + text[end:]

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = index_path.with_name(f'index.html.before_stoprun_swiftdata_{stamp}.bak')
shutil.copy2(index_path, backup)
index_path.write_text(new_text, encoding='utf-8')

print('stopRun() patché: SwiftData-first pour nouvelle course + plan')
print('Backup :', backup)
PY
