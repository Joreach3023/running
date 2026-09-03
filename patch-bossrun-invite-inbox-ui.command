#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

python3 - "$INDEX" <<'PY'
import pathlib, shutil, sys
from datetime import datetime

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = path.with_name(f'index.html.backup_bossinvite_ui_{stamp}')
shutil.copy2(path, backup)
changes=[]

old = ".select('id,run_id,message,created_at,from_profile_id,profiles!from_profile_id(username,avatar),boss_runs!run_id(code,boss_name,event_name,status,ends_at)')"
new = ".select('id,run_id,message,created_at,from_profile_id,from_profile:profiles!rp_invites_from_profile_id_fkey(username,avatar),run:boss_runs!rp_invites_run_id_fkey(code,boss_name,event_name,status,ends_at)')"
if old in text:
    text = text.replace(old, new, 1)
    changes.append('invite-inbox-explicit-joins')
elif new not in text:
    raise SystemExit('ERREUR: requête boîte invitations Boss Run non reconnue.')

old2 = "const from = i.profiles || {};\n      const run = i.boss_runs || {};"
new2 = "const from = i.from_profile || {};\n      const run = i.run || {};"
if old2 in text:
    text = text.replace(old2, new2, 1)
    changes.append('invite-inbox-alias-read')
elif new2 not in text:
    raise SystemExit('ERREUR: lecture alias invitation non reconnue.')

marker = '/* RunPacer Boss invite viewport fix */'
if marker not in text:
    script = r'''
<script>
/* RunPacer Boss invite viewport fix */
(function(){
  function fixBossInviteViewport(){
    const buttons = Array.from(document.querySelectorAll('button[onclick*="brInviteFriend"]'))
      .filter(b => b.offsetParent !== null);
    if (!buttons.length) return;

    const list = buttons[0].parentElement?.parentElement;
    if (list) {
      list.style.maxHeight = 'min(46dvh, 380px)';
      list.style.overflowY = 'auto';
      list.style.webkitOverflowScrolling = 'touch';
      list.style.paddingBottom = 'max(10px, env(safe-area-inset-bottom))';
      list.style.overscrollBehavior = 'contain';
    }

    let node = buttons[0];
    while (node && node !== document.body) {
      const cs = getComputedStyle(node);
      const modalish = cs.position === 'fixed' || /modal|sheet|dialog|overlay/i.test(node.className || '') || /modal|sheet|dialog|overlay/i.test(node.id || '');
      if (modalish) {
        node.style.maxHeight = 'calc(100dvh - max(16px, env(safe-area-inset-top)) - 12px)';
        node.style.overflowY = 'auto';
        node.style.webkitOverflowScrolling = 'touch';
        node.style.paddingBottom = 'max(12px, env(safe-area-inset-bottom))';
        break;
      }
      node = node.parentElement;
    }
  }

  const original = window.brOpenInvite;
  if (typeof original === 'function' && !original.__rpViewportWrapped) {
    const wrapped = function(...args){
      const result = original.apply(this,args);
      [0,80,220,500].forEach(ms => setTimeout(fixBossInviteViewport, ms));
      return result;
    };
    wrapped.__rpViewportWrapped = true;
    window.brOpenInvite = wrapped;
  }

  const obs = new MutationObserver(() => fixBossInviteViewport());
  if (document.body) obs.observe(document.body,{subtree:true,childList:true});
})();
</script>
'''
    if '</body>' not in text:
        raise SystemExit('ERREUR: </body> introuvable.')
    text = text.replace('</body>', script + '\n</body>', 1)
    changes.append('boss-invite-scroll-viewport')

path.write_text(text, encoding='utf-8')
print('Patch Boss Run inbox/UI appliqué.')
for c in changes: print('-', c)
print('Backup:', backup)
print('Aucune donnée locale ou Supabase n\'a été supprimée.')
PY
