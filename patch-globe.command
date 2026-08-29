#!/bin/bash
# ============================================================
# RunPacer — Patch automatique pour ajouter l'animation Globe
# ------------------------------------------------------------
# Double-clique sur ce fichier pour l'exécuter.
# Il modifie ton index.html pour activer l'animation Globe.
# Une sauvegarde .backup est créée avant toute modification.
# ============================================================

cd "$(dirname "$0")"

INDEX="ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "❌ Fichier introuvable : $INDEX"
  echo "   Place ce script à la racine du projet RunPacer."
  read -p "Appuie sur Entrée pour fermer..."
  exit 1
fi

# Sauvegarde datée
BACKUP="${INDEX}.backup-$(date +%Y%m%d-%H%M%S)"
cp "$INDEX" "$BACKUP"
echo "✓ Sauvegarde créée : $BACKUP"

python3 <<'PYEOF'
import re, sys

path = "ios/App/App/public/index.html"
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

modifications = 0

# ---------- Étape 1 : Injection dans le <head> ----------
head_snippet = """    <!-- Animation Globe NASA au lancement de course -->
    <link rel="stylesheet" href="launch-globe.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
    <script src="launch-globe.js"></script>
"""

if "launch-globe.js" in html:
    print("  ℹ️  Head déjà patché (launch-globe.js présent) — skip")
else:
    # On insère juste après la ligne notifications.js
    marker = '<script src="notifications.js"></script>'
    if marker in html:
        html = html.replace(marker, marker + "\n" + head_snippet, 1)
        modifications += 1
        print("  ✓ Scripts ajoutés dans le <head>")
    else:
        print("  ⚠️  Marqueur 'notifications.js' introuvable — head non patché")

# ---------- Étape 2 : Intercepteur de clic sur start-run-btn ----------
hook_snippet = """
            // === Animation globe RunPacer avant le démarrage ===
            (function(){
              const btn = document.getElementById('start-run-btn');
              if(!btn || btn._globeHooked) return;
              btn._globeHooked = true;
              btn.addEventListener('click', function(e){
                if(e._globeBypass) return;
                e.stopImmediatePropagation();
                e.preventDefault();
                if(window.RunpacerLaunchGlobe){
                  window.RunpacerLaunchGlobe.play(() => {
                    const fake = new Event('click');
                    fake._globeBypass = true;
                    btn.dispatchEvent(fake);
                  });
                }
              }, true);
            })();
"""

if "_globeHooked" in html:
    print("  ℹ️  Intercepteur déjà en place — skip")
else:
    # On cherche la première occurrence de addEventListener sur start-run-btn
    pattern = r"(document\.getElementById\(\s*['\"]start-run-btn['\"]\s*\)\s*\.addEventListener\(\s*['\"]click['\"])"
    m = re.search(pattern, html)
    if m:
        # Insérer le hook juste avant ce bloc
        insertion_point = m.start()
        # Remonter jusqu'au début de la ligne pour une indentation propre
        line_start = html.rfind("\n", 0, insertion_point) + 1
        html = html[:line_start] + hook_snippet + "\n" + html[line_start:]
        modifications += 1
        print("  ✓ Intercepteur de clic ajouté avant le listener")
    else:
        print("  ⚠️  Listener 'start-run-btn' introuvable — intercepteur non patché")

# ---------- Sauvegarde ----------
if modifications > 0:
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\n✅ {modifications} modification(s) appliquée(s) à {path}")
else:
    print("\n⚠️  Aucune modification appliquée. Le fichier est peut-être déjà patché.")
PYEOF

echo ""
echo "✨ Terminé ! Lance ton app pour voir l'animation."
echo ""
read -p "Appuie sur Entrée pour fermer cette fenêtre..."
