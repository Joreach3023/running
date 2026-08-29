#!/bin/bash
# ============================================================
# RunPacer — Patch v2 : animation Globe sur TOUS les lancements
# ------------------------------------------------------------
# Cette version intercepte la fonction startCountdown() elle-même,
# ce qui couvre automatiquement tous les boutons qui lancent une
# course : démarrage normal, lancement de séance, reprise après
# pause, etc.
#
# Double-clique pour exécuter. Une sauvegarde est créée avant.
# ============================================================

cd "$(dirname "$0")"

INDEX="ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "❌ Fichier introuvable : $INDEX"
  read -p "Appuie sur Entrée pour fermer..."
  exit 1
fi

BACKUP="${INDEX}.backup-v2-$(date +%Y%m%d-%H%M%S)"
cp "$INDEX" "$BACKUP"
echo "✓ Sauvegarde créée : $BACKUP"

python3 <<'PYEOF'
import re

path = "ios/App/App/public/index.html"
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

modifications = 0

# ============================================================
# Étape 1 : Retirer l'ancien hook v1 sur start-run-btn (si présent)
# ============================================================
# On le reconnait par le commentaire "Animation globe RunPacer avant"
old_hook_pattern = re.compile(
    r"\n?\s*// === Animation globe RunPacer avant le démarrage ===\s*\n"
    r"\s*\(function\(\)\{[^}]*?_globeHooked[^}]*?\}\s*\)\s*\(\s*\)\s*;?",
    re.DOTALL
)
# Version plus permissive : on cherche l'IIFE entière qui contient _globeHooked
old_hook_alt = re.compile(
    r"\n\s*// === Animation globe RunPacer avant le démarrage ===.*?_globeHooked.*?\}\)\(\);?",
    re.DOTALL
)
m = old_hook_alt.search(html)
if m:
    html = html[:m.start()] + html[m.end():]
    modifications += 1
    print("  ✓ Ancien hook v1 retiré")
else:
    print("  ℹ️  Pas d'ancien hook v1 à retirer")

# ============================================================
# Étape 2 : Vérifier que le <head> contient bien les scripts
# ============================================================
if "launch-globe.js" not in html:
    head_snippet = """    <!-- Animation Globe NASA au lancement de course -->
    <link rel="stylesheet" href="launch-globe.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
    <script src="launch-globe.js"></script>
"""
    marker = '<script src="notifications.js"></script>'
    if marker in html:
        html = html.replace(marker, marker + "\n" + head_snippet, 1)
        modifications += 1
        print("  ✓ Scripts ajoutés dans le <head>")
    else:
        print("  ⚠️  Marqueur notifications.js introuvable")
else:
    print("  ℹ️  Scripts déjà présents dans le <head>")

# ============================================================
# Étape 3 : Wrapper autour de startCountdown (le hook universel)
# ============================================================
# On cherche la définition : function startCountdown(callback) {
# Juste APRÈS cette définition, on injecte un wrapper qui remplace
# startCountdown par une version qui joue le globe d'abord.

if "__RP_COUNTDOWN_WRAPPED__" in html:
    print("  ℹ️  Wrapper startCountdown déjà en place — skip")
else:
    # Trouver la fin de la fonction startCountdown originale
    # On cherche : function startCountdown(...) { ... }
    # et on place le wrapper juste après cette fonction.
    #
    # Plus simple : on injecte juste après le DOMContentLoaded qui initialise
    # les event listeners. On met le wrapper dans une balise <script> séparée
    # juste avant </body>, ça s'exécute quand tout est chargé.

    wrapper_snippet = """
<!-- === RunPacer Globe : wrapper universel startCountdown === -->
<script>
  window.__RP_COUNTDOWN_WRAPPED__ = false;
  (function(){
    function wrapWhenReady(){
      if(window.__RP_COUNTDOWN_WRAPPED__) return;
      if(typeof window.startCountdown !== 'function'){
        // Pas encore défini, on réessaie
        return setTimeout(wrapWhenReady, 100);
      }
      if(!window.RunpacerLaunchGlobe){
        // Module pas encore chargé, on réessaie
        return setTimeout(wrapWhenReady, 100);
      }

      const originalCountdown = window.startCountdown;
      window.startCountdown = function(callback){
        // Joue le globe d'abord, puis le countdown original n'est PAS nécessaire
        // (le globe fait déjà son propre 3-2-1). On appelle juste le callback à la fin.
        try{
          window.RunpacerLaunchGlobe.play(function(){
            // Après l'animation, lance le vrai callback (startRun, resumeRun, etc.)
            if(typeof callback === 'function') callback();
          });
        }catch(e){
          console.warn('[RP Globe] fallback vers countdown original', e);
          originalCountdown.call(this, callback);
        }
      };

      window.__RP_COUNTDOWN_WRAPPED__ = true;
      console.log('[RunPacer Globe] startCountdown wrappé — animation active sur tous les lancements');
    }
    // Tenter immédiatement, puis au DOMContentLoaded, puis au window load
    wrapWhenReady();
    document.addEventListener('DOMContentLoaded', wrapWhenReady);
    window.addEventListener('load', wrapWhenReady);
  })();
</script>
"""

    # Insérer juste avant </body>
    if "</body>" in html:
        html = html.replace("</body>", wrapper_snippet + "\n</body>", 1)
        modifications += 1
        print("  ✓ Wrapper universel startCountdown ajouté avant </body>")
    else:
        print("  ⚠️  Balise </body> introuvable")

# ============================================================
# Sauvegarde
# ============================================================
if modifications > 0:
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\n✅ {modifications} modification(s) appliquée(s)")
else:
    print("\n⚠️  Aucune modification appliquée")

PYEOF

echo ""
echo "✨ Patch v2 terminé."
echo ""
echo "⚠️  IMPORTANT pour iPhone via Xcode :"
echo "   1. Dans Xcode : Product → Clean Build Folder (Cmd+Shift+K)"
echo "   2. Puis : Product → Build (Cmd+B)"
echo "   3. Lance l'app sur ton iPhone"
echo "   Sinon iOS utilise l'ancienne version en cache."
echo ""
read -p "Appuie sur Entrée pour fermer..."
