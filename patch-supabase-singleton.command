#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_DIR="$ROOT_DIR/ios/App/App/public"
INDEX="$PUBLIC_DIR/index.html"
NOTIFICATIONS="$PUBLIC_DIR/notifications.js"
SINGLETON="$PUBLIC_DIR/runpacer-supabase-singleton.js"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi
if [ ! -f "$NOTIFICATIONS" ]; then
  echo "ERREUR: notifications.js introuvable: $NOTIFICATIONS"
  exit 1
fi

python3 - "$INDEX" "$NOTIFICATIONS" "$SINGLETON" <<'PY'
import pathlib
import re
import shutil
import sys
from datetime import datetime

index_path = pathlib.Path(sys.argv[1])
notifications_path = pathlib.Path(sys.argv[2])
singleton_path = pathlib.Path(sys.argv[3])

SUPA_URL = "https://yibfsniqbivhahyjxcmk.supabase.co"
SUPA_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlpYmZzbmlxYml2aGFoeWp4Y21rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ1NDczNjEsImV4cCI6MjA5MDEyMzM2MX0.Vdw-VJ2UpffEuIW1jtb-Zn3ufLdVRTIhPJvkSPrOnow"

index = index_path.read_text(encoding="utf-8")
notifications = notifications_path.read_text(encoding="utf-8")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup_dir = index_path.parent / f".backup_supabase_singleton_{stamp}"
backup_dir.mkdir(parents=True, exist_ok=True)
shutil.copy2(index_path, backup_dir / "index.html.bak")
shutil.copy2(notifications_path, backup_dir / "notifications.js.bak")
if singleton_path.exists():
    shutil.copy2(singleton_path, backup_dir / "runpacer-supabase-singleton.js.bak")

singleton_js = f'''// RunPacer — single shared Supabase browser client
// All browser features must reuse this instance so GoTrue owns one auth session.
(function (global) {{
  'use strict';

  const SUPA_URL = {SUPA_URL!r};
  const SUPA_KEY = {SUPA_KEY!r};

  global.rpGetSupabaseClient = function rpGetSupabaseClient() {{
    if (global.RunPacerSupabase) return global.RunPacerSupabase;

    if (!global.supabase || typeof global.supabase.createClient !== 'function') {{
      console.warn('[Supabase] Librairie indisponible; client partagé non créé.');
      return null;
    }}

    global.RunPacerSupabase = global.supabase.createClient(SUPA_URL, SUPA_KEY);
    global.__rpSupabaseClientCreateCount = (global.__rpSupabaseClientCreateCount || 0) + 1;
    console.log('[Supabase] Client partagé RunPacer créé.');
    return global.RunPacerSupabase;
  }};

  // The CDN script is loaded immediately before this file in index.html.
  global.rpGetSupabaseClient();
}})(window);
'''
singleton_path.write_text(singleton_js, encoding="utf-8")

# Replace the one onboarding client that hard-codes URL/key directly.
onboarding_pattern = re.compile(
    r"supabase\.createClient\(\s*['\"]" + re.escape(SUPA_URL) +
    r"['\"]\s*,\s*['\"]" + re.escape(SUPA_KEY) + r"['\"]\s*\)",
    re.MULTILINE,
)
index, onboarding_count = onboarding_pattern.subn("window.rpGetSupabaseClient()", index)

# Replace Boss Run, invite-friends, social and backup clients.
index, variable_count = re.subn(
    r"supabase\.createClient\(\s*SUPA_URL\s*,\s*SUPA_KEY\s*\)",
    "window.rpGetSupabaseClient()",
    index,
)

replacement_count = onboarding_count + variable_count
if replacement_count not in (0, 5):
    raise SystemExit(
        f"ERREUR: {replacement_count} création(s) Supabase remplacée(s) dans index.html; 5 attendues. "
        "Les backups ont été conservés."
    )

# Inject the singleton immediately after the Supabase UMD CDN script.
script_tag = '<script src="runpacer-supabase-singleton.js"></script>'
if script_tag not in index:
    cdn_pattern = re.compile(
        r'(<script\s+src=["\'][^"\']*supabase-js@2/dist/umd/supabase\.js["\']\s*>\s*</script>)',
        re.IGNORECASE,
    )
    index, inject_count = cdn_pattern.subn(r"\1\n    " + script_tag, index, count=1)
    if inject_count != 1:
        raise SystemExit("ERREUR: balise CDN Supabase introuvable; singleton non injecté.")

# notifications.js must reuse the same global client. Keep a lazy one-time fallback
# in case script loading order changes in a future build.
notifications_pattern = re.compile(
    r"function\s+supa\(\)\s*\{\s*"
    r"return\s*\(typeof\s+supabase\s*!==\s*['\"]undefined['\"]\)\s*\?\s*"
    r"supabase\.createClient\(SUPA_URL,\s*SUPA_KEY\)\s*:\s*null;\s*\}",
    re.MULTILINE,
)
notifications_replacement = '''function supa() {
    if (window.RunPacerSupabase) return window.RunPacerSupabase;
    if (typeof window.rpGetSupabaseClient === 'function') return window.rpGetSupabaseClient();
    if (typeof supabase === 'undefined' || typeof supabase.createClient !== 'function') return null;

    // Defensive fallback only if notifications.js ever loads before the singleton helper.
    window.RunPacerSupabase = supabase.createClient(SUPA_URL, SUPA_KEY);
    window.__rpSupabaseClientCreateCount = (window.__rpSupabaseClientCreateCount || 0) + 1;
    return window.RunPacerSupabase;
  }'''
notifications, notification_count = notifications_pattern.subn(notifications_replacement, notifications, count=1)

if notification_count == 0 and "window.RunPacerSupabase" not in notifications:
    raise SystemExit("ERREUR: fonction supa() de notifications.js non reconnue.")

index_path.write_text(index, encoding="utf-8")
notifications_path.write_text(notifications, encoding="utf-8")

remaining_index_creates = len(re.findall(r"supabase\.createClient\s*\(", index))
if remaining_index_creates != 0:
    raise SystemExit(
        f"ERREUR: il reste {remaining_index_creates} supabase.createClient(...) dans index.html."
    )

print("Patch Supabase singleton appliqué.")
print(f"- Remplacements index.html cette exécution : {replacement_count}")
print("- Client partagé : runpacer-supabase-singleton.js")
print("- notifications.js : client partagé + fallback unique")
print("- Backup :", backup_dir)
print("Aucune donnée Supabase n'a été modifiée.")
PY
