#!/bin/bash
# =============================================================================
#  RunPacer — Patch v4
#  Fixes the 7 visual bugs on the Strava-style course skin:
#    1. Map not fullscreen
#    2. "Carte de suivi GPS" fallback text visible
#    3. Leaflet zoom controls visible
#    4. Double icons on pause/stop buttons
#    5. Faded button colors
#    6. Leaflet/OSM attribution visible
#    7. "Terminer" does not navigate to stats-section
# =============================================================================
set -e

APP_DIR="/Users/jonathanlabbe/runpacer/ios/App/App/public"
INDEX="$APP_DIR/index.html"
CSS_FILE="$APP_DIR/run-strava-skin.css"
JS_FILE="$APP_DIR/run-strava-skin.js"

echo ""
echo "============================================================"
echo "  RunPacer — Patch v4"
echo "============================================================"
echo ""
echo "Dossier app : $APP_DIR"
echo ""

if [ ! -d "$APP_DIR" ]; then
    echo "[ERREUR] Impossible de trouver le dossier de l'app :"
    echo "         $APP_DIR"
    echo ""
    echo "Assure-toi que le projet RunPacer est bien à cet emplacement."
    read -p "Appuie sur Entrée pour fermer..."
    exit 1
fi

# -----------------------------------------------------------------------------
# 1) Backup
# -----------------------------------------------------------------------------
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$APP_DIR/.backup_v4_$STAMP"
mkdir -p "$BACKUP_DIR"
[ -f "$CSS_FILE" ] && cp "$CSS_FILE" "$BACKUP_DIR/run-strava-skin.css.bak"
[ -f "$JS_FILE" ] && cp "$JS_FILE" "$BACKUP_DIR/run-strava-skin.js.bak"
[ -f "$INDEX" ] && cp "$INDEX" "$BACKUP_DIR/index.html.bak"
echo "[1/5] Backup créé dans : $BACKUP_DIR"

# -----------------------------------------------------------------------------
# 2) Write the new CSS
# -----------------------------------------------------------------------------
cat > "$CSS_FILE" <<'RP_CSS_EOF'
/* ==========================================================================
   RunPacer — Strava-style course skin v4
   ========================================================================== */

body.rp-course-active .bottom-nav,
body.rp-course-active nav,
body.rp-course-active #run-type-selector,
body.rp-course-active #run-params-panel,
body.rp-course-active #current-pace-card,
body.rp-course-active .section:not(#run-section),
body.rp-course-active .page-header,
body.rp-course-active .header-bar {
    display: none !important;
}

body.rp-course-active #run-section,
body.rp-course-active #run-section.active {
    position: fixed !important;
    inset: 0 !important;
    top: 0 !important; left: 0 !important; right: 0 !important; bottom: 0 !important;
    width: 100vw !important;
    height: 100vh !important;
    height: 100dvh !important;
    margin: 0 !important;
    padding: 0 !important;
    z-index: 900 !important;
    background: #0f1116 !important;
    overflow: hidden !important;
}

body.rp-course-active #map,
body.rp-course-active #run-section #map {
    position: fixed !important;
    inset: 0 !important;
    top: 0 !important; left: 0 !important; right: 0 !important; bottom: 0 !important;
    width: 100vw !important;
    height: 100vh !important;
    height: 100dvh !important;
    margin: 0 !important;
    padding: 0 !important;
    border-radius: 0 !important;
    z-index: 1 !important;
    background: #0f1116 !important;
}

/* Hide the "Carte de suivi GPS" fallback div the app injects into #map */
body.rp-course-active #map > div:not(.leaflet-pane):not(.leaflet-control-container):not(.leaflet-map-pane):not(.leaflet-proxy) {
    display: none !important;
}

/* Hide Leaflet UI chrome */
body.rp-course-active .leaflet-control-container,
body.rp-course-active .leaflet-control-zoom,
body.rp-course-active .leaflet-control-attribution,
body.rp-course-active .leaflet-top,
body.rp-course-active .leaflet-bottom {
    display: none !important;
    visibility: hidden !important;
    opacity: 0 !important;
    pointer-events: none !important;
}

/* Top header */
body.rp-course-active #rp-run-header {
    position: fixed;
    top: env(safe-area-inset-top, 0);
    left: 0; right: 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 18px;
    z-index: 950;
    background: linear-gradient(180deg, rgba(15,17,22,0.85) 0%, rgba(15,17,22,0) 100%);
    color: #fff;
    font-family: -apple-system, BlinkMacSystemFont, "Inter", sans-serif;
    pointer-events: none;
}

body.rp-course-active #rp-run-header .rp-session-title {
    font-size: 17px; font-weight: 700; letter-spacing: 0.3px;
    text-shadow: 0 2px 8px rgba(0,0,0,0.6);
}

body.rp-course-active #rp-run-header .rp-gps-pill {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 6px 11px;
    background: rgba(34,197,94,0.22);
    border: 1px solid rgba(34,197,94,0.55);
    border-radius: 999px;
    font-size: 12px; font-weight: 600; color: #4ade80;
    backdrop-filter: blur(10px);
    -webkit-backdrop-filter: blur(10px);
}

body.rp-course-active #rp-run-header .rp-gps-pill::before {
    content: ""; width: 7px; height: 7px; border-radius: 50%;
    background: #22c55e; box-shadow: 0 0 8px #22c55e;
    animation: rp-pulse-dot 1.4s ease-in-out infinite;
}

@keyframes rp-pulse-dot {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.5; transform: scale(0.85); }
}

/* Floating metrics overlay */
body.rp-course-active .metrics-row {
    position: fixed !important;
    left: 12px !important; right: 12px !important;
    bottom: calc(env(safe-area-inset-bottom, 0) + 140px) !important;
    top: auto !important;
    display: flex !important;
    flex-direction: row !important;
    gap: 10px !important;
    padding: 16px 14px !important;
    margin: 0 !important;
    background: rgba(15, 17, 22, 0.72) !important;
    backdrop-filter: blur(22px) saturate(160%) !important;
    -webkit-backdrop-filter: blur(22px) saturate(160%) !important;
    border: 1px solid rgba(255,255,255,0.08) !important;
    border-radius: 22px !important;
    box-shadow: 0 12px 40px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.06) !important;
    z-index: 940 !important;
    color: #fff !important;
}

body.rp-course-active .metric-box {
    flex: 1 1 0 !important;
    min-width: 0 !important;
    display: flex !important;
    flex-direction: column !important;
    align-items: center !important;
    justify-content: center !important;
    background: transparent !important;
    border: none !important;
    padding: 4px 2px !important;
    text-align: center !important;
}

body.rp-course-active .metric-box + .metric-box {
    border-left: 1px solid rgba(255,255,255,0.10) !important;
}

body.rp-course-active .metric-box-value {
    font-size: 26px !important;
    font-weight: 800 !important;
    line-height: 1.1 !important;
    color: #fff !important;
    letter-spacing: -0.5px !important;
    font-variant-numeric: tabular-nums !important;
    font-family: -apple-system, BlinkMacSystemFont, "Inter", sans-serif !important;
}

body.rp-course-active .metric-box:first-child .metric-box-value {
    font-size: 36px !important;
    color: #fb923c !important;
    text-shadow: 0 2px 14px rgba(251,146,60,0.35) !important;
}

body.rp-course-active .metric-box-label {
    margin-top: 4px !important;
    font-size: 10px !important;
    font-weight: 700 !important;
    letter-spacing: 1.3px !important;
    text-transform: uppercase !important;
    color: rgba(255,255,255,0.55) !important;
}

/* Control buttons */
body.rp-course-active .run-controls,
body.rp-course-active #run-section .run-controls {
    position: fixed !important;
    left: 0 !important; right: 0 !important;
    bottom: calc(env(safe-area-inset-bottom, 0) + 28px) !important;
    display: flex !important;
    flex-direction: row !important;
    align-items: center !important;
    justify-content: center !important;
    gap: 18px !important;
    padding: 0 20px !important;
    margin: 0 !important;
    z-index: 945 !important;
    background: transparent !important;
}

body.rp-course-active .run-controls > button,
body.rp-course-active .run-controls > .btn {
    width: 64px !important; height: 64px !important;
    min-width: 64px !important; min-height: 64px !important;
    padding: 0 !important; margin: 0 !important;
    border-radius: 50% !important;
    border: none !important;
    box-shadow: 0 8px 24px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.15) !important;
    display: inline-flex !important;
    align-items: center !important;
    justify-content: center !important;
    color: #fff !important;
    font-size: 24px !important;
    cursor: pointer !important;
    transition: transform 0.15s ease, box-shadow 0.15s ease !important;
    position: relative !important;
    opacity: 1 !important;
}

body.rp-course-active .run-controls > button:active { transform: scale(0.93) !important; }

body.rp-course-active .run-controls > button[disabled] {
    opacity: 0.45 !important;
    cursor: not-allowed !important;
}

body.rp-course-active #pause-btn {
    width: 80px !important; height: 80px !important;
    min-width: 80px !important; min-height: 80px !important;
    background: linear-gradient(135deg, #fb923c 0%, #f97316 100%) !important;
    box-shadow: 0 10px 30px rgba(249,115,22,0.55), inset 0 1px 0 rgba(255,255,255,0.2) !important;
    order: 2 !important;
}

body.rp-course-active #stop-btn {
    background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%) !important;
    box-shadow: 0 8px 24px rgba(220,38,38,0.5), inset 0 1px 0 rgba(255,255,255,0.2) !important;
    order: 3 !important;
}

body.rp-course-active #rp-lap-btn {
    background: rgba(30,32,40,0.85) !important;
    border: 1px solid rgba(255,255,255,0.12) !important;
    order: 1 !important;
}

body.rp-course-active #rp-lock-btn {
    background: rgba(30,32,40,0.85) !important;
    border: 1px solid rgba(255,255,255,0.12) !important;
    order: 4 !important;
}

body.rp-course-active .run-controls > button svg,
body.rp-course-active .run-controls > button i[data-lucide] {
    width: 28px !important; height: 28px !important;
    stroke-width: 2.4 !important;
    display: inline-block !important;
    color: #fff !important;
    fill: currentColor !important;
}

body.rp-course-active #pause-btn svg,
body.rp-course-active #pause-btn i[data-lucide] {
    width: 34px !important; height: 34px !important;
}

/* KILL any ::before/::after emoji icons that older skins may add (no double icons!) */
body.rp-course-active .run-controls > button::before,
body.rp-course-active .run-controls > button::after,
body.rp-course-active #pause-btn::before,
body.rp-course-active #pause-btn::after,
body.rp-course-active #stop-btn::before,
body.rp-course-active #stop-btn::after {
    content: none !important;
    display: none !important;
}

/* Toast */
body.rp-course-active .rp-toast {
    position: fixed;
    left: 50%;
    top: calc(env(safe-area-inset-top, 0) + 72px);
    transform: translateX(-50%);
    padding: 10px 16px;
    background: rgba(15,17,22,0.9);
    color: #fff;
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 999px;
    font-size: 13px; font-weight: 600;
    z-index: 960;
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    opacity: 0; pointer-events: none;
    transition: opacity 0.25s ease, transform 0.25s ease;
}

body.rp-course-active .rp-toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
RP_CSS_EOF

echo "[2/5] run-strava-skin.css écrit"

# -----------------------------------------------------------------------------
# 3) Write the new JS
# -----------------------------------------------------------------------------
cat > "$JS_FILE" <<'RP_JS_EOF'
/* RunPacer — Strava skin v4 */
(function(){
    'use strict';

    var COURSE_CLASS = 'rp-course-active';
    var active = false;
    var observer = null;

    function $(sel){ return document.querySelector(sel); }
    function $$(sel){ return Array.prototype.slice.call(document.querySelectorAll(sel)); }

    function toast(msg, ms){
        ms = ms || 1800;
        var t = document.createElement('div');
        t.className = 'rp-toast';
        t.textContent = msg;
        document.body.appendChild(t);
        requestAnimationFrame(function(){ t.classList.add('show'); });
        setTimeout(function(){
            t.classList.remove('show');
            setTimeout(function(){ if(t.parentNode) t.parentNode.removeChild(t); }, 300);
        }, ms);
    }

    function buildHeader(sessionName){
        var existing = document.getElementById('rp-run-header');
        if(existing) existing.remove();
        var header = document.createElement('div');
        header.id = 'rp-run-header';
        header.innerHTML = '<div class="rp-session-title"></div><div class="rp-gps-pill">GPS</div>';
        header.querySelector('.rp-session-title').textContent = sessionName || 'Course en cours';
        document.body.appendChild(header);
    }

    function removeHeader(){
        var h = document.getElementById('rp-run-header');
        if(h) h.remove();
    }

    function cleanMap(){
        var mapEl = document.getElementById('map');
        if(mapEl){
            Array.prototype.slice.call(mapEl.children).forEach(function(child){
                var cls = child.className || '';
                if(typeof cls !== 'string') cls = '';
                if(cls.indexOf('leaflet') === -1){
                    child.style.display = 'none';
                }
            });
        }

        try {
            var map = window.mapObject || window.map;
            if(map){
                if(map.zoomControl && typeof map.zoomControl.remove === 'function'){
                    map.zoomControl.remove();
                }
                if(map.attributionControl && typeof map.attributionControl.remove === 'function'){
                    map.attributionControl.remove();
                }
                setTimeout(function(){ if(map.invalidateSize) map.invalidateSize(true); }, 120);
                setTimeout(function(){ if(map.invalidateSize) map.invalidateSize(true); }, 500);
            }
        } catch(e){ console.warn('[RP skin] map cleanup failed:', e); }

        $$('.leaflet-control-container, .leaflet-control-zoom, .leaflet-control-attribution').forEach(function(n){
            n.style.display = 'none';
        });
    }

    function watchMap(){
        var mapEl = document.getElementById('map');
        if(!mapEl) return;
        if(observer){ try { observer.disconnect(); } catch(e){} }
        observer = new MutationObserver(function(){ if(active) cleanMap(); });
        observer.observe(mapEl, { childList: true, subtree: true });
    }

    function unwatchMap(){
        if(observer){ try { observer.disconnect(); } catch(e){} observer = null; }
    }

    function activate(sessionName){
        if(active) return;
        active = true;
        document.body.classList.add(COURSE_CLASS);
        buildHeader(sessionName);
        setTimeout(cleanMap, 50);
        setTimeout(cleanMap, 250);
        setTimeout(cleanMap, 800);
        setTimeout(cleanMap, 1500);
        watchMap();
        toast('Course en cours', 1600);
    }

    function deactivate(){
        if(!active) return;
        active = false;
        document.body.classList.remove(COURSE_CLASS);
        removeHeader();
        unwatchMap();
    }

    function gotoStats(){
        try {
            var sections = document.querySelectorAll('.section');
            sections.forEach(function(s){ s.classList.remove('active'); });
            var stats = document.getElementById('stats-section');
            if(stats){
                stats.classList.add('active');
                stats.style.display = '';
                window.scrollTo(0, 0);
            }
        } catch(e){ console.warn('[RP skin] gotoStats failed:', e); }
    }

    function wrapFn(name, before, after){
        var original = window[name];
        if(typeof original !== 'function') return false;
        window[name] = function(){
            var args = arguments;
            try { if(before) before.apply(this, args); } catch(e){ console.warn('[RP skin] before '+name, e); }
            var ret;
            try { ret = original.apply(this, args); } catch(e){ console.warn('[RP skin] original '+name, e); }
            try { if(after) after.apply(this, args); } catch(e){ console.warn('[RP skin] after '+name, e); }
            return ret;
        };
        return true;
    }

    function installHooks(){
        wrapFn('startRun', function(){
            var sessionName = '';
            try {
                var titleEl = document.querySelector('#run-params-panel h2, #run-params-panel h3, .run-title');
                if(titleEl) sessionName = titleEl.textContent.trim();
            } catch(e){}
            activate(sessionName);
        }, null);
        wrapFn('resumeRun', function(){ activate(); }, null);
        wrapFn('stopRun', null, function(){ deactivate(); setTimeout(gotoStats, 40); });
        wrapFn('endRun', null, function(){ deactivate(); setTimeout(gotoStats, 40); });
        wrapFn('finishRun', null, function(){ deactivate(); setTimeout(gotoStats, 40); });

        var stopBtn = document.getElementById('stop-btn');
        if(stopBtn && !stopBtn.__rpStopHooked){
            stopBtn.__rpStopHooked = true;
            stopBtn.addEventListener('click', function(){
                setTimeout(function(){ deactivate(); gotoStats(); }, 120);
            });
        }
    }

    window.RunpacerStravaSkin = {
        activate: activate,
        deactivate: deactivate,
        gotoStats: gotoStats,
        cleanMap: cleanMap,
        _installHooks: installHooks
    };

    function boot(){
        installHooks();
        setTimeout(installHooks, 400);
        setTimeout(installHooks, 1500);
    }

    if(document.readyState === 'complete' || document.readyState === 'interactive'){
        boot();
    } else {
        document.addEventListener('DOMContentLoaded', boot);
    }
})();
RP_JS_EOF

echo "[3/5] run-strava-skin.js écrit"

# -----------------------------------------------------------------------------
# 4) Make sure index.html loads the CSS + JS
# -----------------------------------------------------------------------------
python3 - <<'PY_EOF'
import re, sys, os

index_path = "/Users/jonathanlabbe/runpacer/ios/App/App/public/index.html"
if not os.path.exists(index_path):
    print("[ERREUR] index.html introuvable :", index_path)
    sys.exit(1)

with open(index_path, "r", encoding="utf-8") as f:
    html = f.read()

changed = False

# Ensure CSS is in <head>
css_link = '<link rel="stylesheet" href="run-strava-skin.css?v=4">'
if 'run-strava-skin.css' not in html:
    html = html.replace('</head>', '    ' + css_link + '\n</head>', 1)
    changed = True
else:
    # bump cache-buster
    html = re.sub(
        r'<link[^>]*href="run-strava-skin\.css[^"]*"[^>]*>',
        css_link,
        html
    )
    changed = True

# Ensure JS is before </body>
js_script = '<script src="run-strava-skin.js?v=4"></script>'
if 'run-strava-skin.js' not in html:
    html = html.replace('</body>', '    ' + js_script + '\n</body>', 1)
    changed = True
else:
    html = re.sub(
        r'<script[^>]*src="run-strava-skin\.js[^"]*"[^>]*></script>',
        js_script,
        html
    )
    changed = True

if changed:
    with open(index_path, "w", encoding="utf-8") as f:
        f.write(html)
    print("[4/5] index.html mis à jour (CSS + JS liés, cache-buster v=4)")
else:
    print("[4/5] index.html déjà correct")
PY_EOF

# -----------------------------------------------------------------------------
# 5) Done
# -----------------------------------------------------------------------------
echo ""
echo "[5/5] Patch v4 appliqué avec succès !"
echo ""
echo "============================================================"
echo "  PROCHAINES ÉTAPES"
echo "============================================================"
echo ""
echo "1. Ouvre Xcode"
echo "2. Menu : Product → Clean Build Folder  (⇧⌘K)"
echo "3. Build & Run sur ton iPhone"
echo "4. Lance une course et teste :"
echo "   - carte plein écran (pas de zone grise en bas)"
echo "   - pas de texte 'Carte de suivi GPS'"
echo "   - pas de boutons +/− Leaflet"
echo "   - pas de mention OpenStreetMap"
echo "   - boutons pause (orange vif) et stop (rouge vif) avec UNE SEULE icône"
echo "   - Terminer → arrive bien sur la page des statistiques"
echo ""
echo "Si besoin de rollback, backup dans :"
echo "   $BACKUP_DIR"
echo ""
read -p "Appuie sur Entrée pour fermer..."
