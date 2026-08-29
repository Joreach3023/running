#!/bin/bash
# ============================================================
# RunPacer — Patch v3 : Globe NASA + Skin Strava pour course
# ------------------------------------------------------------
# Cette version :
#   1. Active l'animation globe sur TOUS les boutons qui lancent
#      une course (via wrapper sur startCountdown).
#   2. Corrige le double 3-2-1 (le globe remplace le countdown).
#   3. Ajoute le skin "Strava" : map plein écran + overlay
#      transparent + boutons flottants (pause, stop, lock, lap)
#      quand tu es EN COURSE.
#   4. Retour au style normal quand tu termines la course.
#
# Double-clique pour exécuter. Sauvegarde automatique.
# ============================================================

cd "$(dirname "$0")"
INDEX="ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "❌ Fichier introuvable : $INDEX"
  read -p "Appuie sur Entrée pour fermer..."
  exit 1
fi

BACKUP="${INDEX}.backup-v3-$(date +%Y%m%d-%H%M%S)"
cp "$INDEX" "$BACKUP"
echo "✓ Sauvegarde créée : $BACKUP"

python3 <<'PYEOF'
import re

path = "ios/App/App/public/index.html"
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

modifications = 0

# ============================================================
# Étape 1 : Nettoyer l'ancien hook v1 (sur start-run-btn) s'il traîne
# ============================================================
old_hook = re.search(
    r"\n\s*// === Animation globe RunPacer avant le démarrage ===.*?_globeHooked.*?\}\)\(\);?",
    html, re.DOTALL
)
if old_hook:
    html = html[:old_hook.start()] + html[old_hook.end():]
    modifications += 1
    print("  ✓ Ancien hook v1 retiré")

# ============================================================
# Étape 2 : Assurer les 3 scripts dans le <head> (Three + CSS + JS globe)
# ============================================================
head_needed = []
if "launch-globe.css" not in html: head_needed.append('    <link rel="stylesheet" href="launch-globe.css">')
if "three.min.js" not in html: head_needed.append('    <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>')
if "launch-globe.js" not in html: head_needed.append('    <script src="launch-globe.js"></script>')
# Nouveaux fichiers pour le skin Strava
if "run-strava-skin.css" not in html: head_needed.append('    <link rel="stylesheet" href="run-strava-skin.css">')
if "run-strava-skin.js" not in html: head_needed.append('    <script src="run-strava-skin.js"></script>')

if head_needed:
    head_block = "    <!-- RunPacer : Globe NASA + Skin Strava -->\n" + "\n".join(head_needed) + "\n"
    marker = '<script src="notifications.js"></script>'
    if marker in html:
        html = html.replace(marker, marker + "\n" + head_block, 1)
        modifications += 1
        print(f"  ✓ {len(head_needed)} script(s)/CSS ajoutés dans le <head>")
    else:
        print("  ⚠️  Marqueur notifications.js introuvable")
else:
    print("  ℹ️  Tous les scripts déjà présents dans le <head>")

# ============================================================
# Étape 3 : Wrapper universel sur startCountdown (avant </body>)
# ============================================================
if "__RP_COUNTDOWN_WRAPPED__" in html:
    print("  ℹ️  Wrapper startCountdown déjà en place")
else:
    wrapper_snippet = """
<!-- === RunPacer Globe : wrapper universel startCountdown === -->
<script>
  window.__RP_COUNTDOWN_WRAPPED__ = false;
  (function(){
    function wrapWhenReady(){
      if(window.__RP_COUNTDOWN_WRAPPED__) return;
      if(typeof window.startCountdown !== 'function'){
        return setTimeout(wrapWhenReady, 100);
      }
      if(!window.RunpacerLaunchGlobe){
        return setTimeout(wrapWhenReady, 100);
      }
      const originalCountdown = window.startCountdown;
      window.startCountdown = function(callback){
        try{
          window.RunpacerLaunchGlobe.play(function(){
            if(typeof callback === 'function') callback();
          });
        }catch(e){
          console.warn('[RP Globe] fallback vers countdown original', e);
          originalCountdown.call(this, callback);
        }
      };
      window.__RP_COUNTDOWN_WRAPPED__ = true;
      console.log('[RunPacer] Globe animation active sur tous les lancements');
    }
    wrapWhenReady();
    document.addEventListener('DOMContentLoaded', wrapWhenReady);
    window.addEventListener('load', wrapWhenReady);
  })();
</script>
"""
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
    print("\n⚠️  Aucune modification appliquée (déjà patché)")

PYEOF

echo ""
echo "✨ Patch v3 terminé."
echo ""
echo "⚠️  Pour que ça marche sur iPhone :"
echo "   1. Dans Xcode : Product → Clean Build Folder (Cmd+Shift+K)"
echo "   2. Product → Build (Cmd+B)"
echo "   3. Lance l'app sur ton iPhone"
echo ""
read -p "Appuie sur Entrée pour fermer..."
