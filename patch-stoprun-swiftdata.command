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
primary_marker = '// RunPacer SwiftData-first completed-run save'
final_marker = '// RunPacer compatibility-only localStorage write'

start = text.find('async function stopRun()')
if start == -1:
    raise SystemExit('ERREUR: async function stopRun() introuvable')

end_marker = '// Réafficher le bouton profil'
end = text.find(end_marker, start)
if end == -1:
    raise SystemExit('ERREUR: fin du bloc stopRun() introuvable')

changed = False

# -------------------------------------------------------------------------
# Phase 1: direct SwiftData write for the completed run + training plan.
# Skip safely when the first patch is already present locally.
# -------------------------------------------------------------------------
if primary_marker not in text[start:end]:
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
{indent}// Si cette écriture échoue, localStorage conserve la course pour la récupération au prochain démarrage.
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
{indent}userData.runs.unshift(newRun); // Compatibilité UI + fallback de récupération'''

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

{indent}// Stockage local conservé pour l'ancienne UI et comme filet de récupération.
{indent}localStorage.setItem('runPacerUserData', JSON.stringify(userData));'''

    segment = segment[:local_match.start()] + local_replacement + segment[local_match.end():]
    text = text[:start] + segment + text[end:]
    changed = True
    print('Phase 1: stopRun() patché en SwiftData-first')
else:
    print('Phase 1: stopRun() était déjà SwiftData-first')

# Refresh bounds after phase 1 because text length may have changed.
start = text.find('async function stopRun()')
end = text.find(end_marker, start)
segment = text[start:end]

# -------------------------------------------------------------------------
# Phase 2: mark the legacy userData write as compatibility-only. Training
# and personal-state hooks already recognize this shared depth marker and
# will not write their SwiftData records back from this hydration write.
# -------------------------------------------------------------------------
if final_marker not in segment:
    local_call = "localStorage.setItem('runPacerUserData', JSON.stringify(userData));"
    pos = segment.find(local_call)
    if pos == -1:
        raise SystemExit('ERREUR: écriture locale finale runPacerUserData introuvable')

    line_start = segment.rfind('\n', 0, pos) + 1
    indent = segment[line_start:pos]
    if indent.strip():
        raise SystemExit('ERREUR: indentation inattendue pour runPacerUserData')

    replacement = f'''{indent}// RunPacer compatibility-only localStorage write
{indent}// Ne doit pas repartir vers les bridges SwiftData dédiés.
{indent}window.__runPacerSwiftDataCompatibilityWriteDepth =
{indent}    Number(window.__runPacerSwiftDataCompatibilityWriteDepth || 0) + 1;
{indent}try {{
{indent}    localStorage.setItem('runPacerUserData', JSON.stringify(userData));
{indent}}} finally {{
{indent}    window.__runPacerSwiftDataCompatibilityWriteDepth = Math.max(
{indent}        0,
{indent}        Number(window.__runPacerSwiftDataCompatibilityWriteDepth || 1) - 1
{indent}    );
{indent}}}'''

    segment = segment[:line_start] + replacement + segment[pos + len(local_call):]
    text = text[:start] + segment + text[end:]
    changed = True
    print('Phase 2: localStorage marqué comme compatibilité uniquement')
else:
    print('Phase 2: écriture de compatibilité déjà finalisée')

if not changed:
    print('Aucun changement nécessaire')
    raise SystemExit(0)

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = index_path.with_name(f'index.html.before_stoprun_swiftdata_{stamp}.bak')
shutil.copy2(index_path, backup)
index_path.write_text(text, encoding='utf-8')

print('stopRun() finalisé: SwiftData direct + localStorage compatibilité/récupération')
print('Backup :', backup)
PY
