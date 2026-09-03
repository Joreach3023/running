#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

python3 - "$INDEX" <<'PY'
import pathlib, re, shutil, subprocess, sys, tempfile
from datetime import datetime

path = pathlib.Path(sys.argv[1])
root = path.parent
current = path.read_text(encoding='utf-8')


def inline_scripts(html):
    out=[]
    for m in re.finditer(r'<script([^>]*)>(.*?)</script>', html, re.S|re.I):
        attrs=m.group(1) or ''
        body=m.group(2) or ''
        if re.search(r'\bsrc\s*=', attrs, re.I):
            continue
        typem=re.search(r'\btype\s*=\s*["\']([^"\']+)', attrs, re.I)
        if typem and typem.group(1).lower() not in ('text/javascript','application/javascript','module'):
            continue
        out.append((m.start(), body))
    return out


def check_html(html):
    errors=[]
    for idx,(start,body) in enumerate(inline_scripts(html),1):
        if not body.strip():
            continue
        # Le code actuel n'utilise pas de modules inline; node --check suffit.
        with tempfile.NamedTemporaryFile('w',suffix='.js',delete=False,encoding='utf-8') as f:
            f.write(body)
            tmp=f.name
        try:
            p=subprocess.run(['node','--check',tmp],capture_output=True,text=True)
        finally:
            pathlib.Path(tmp).unlink(missing_ok=True)
        if p.returncode != 0:
            line = html.count('\n',0,start)+1
            errors.append((idx,line,(p.stderr or p.stdout).strip()))
    return errors


# Trouver un backup PHASE 3 réellement valide, du plus récent au plus ancien.
backups=sorted(root.glob('index.html.backup_social_phase3_*'), key=lambda p:p.stat().st_mtime, reverse=True)
valid_backup=None
valid_html=None
for b in backups:
    try:
        html=b.read_text(encoding='utf-8')
    except Exception:
        continue
    if 'function rpLoadFeed' not in html:
        continue
    if check_html(html):
        continue
    valid_backup=b
    valid_html=html
    break

if valid_backup is None:
    print('ERREUR: aucun backup social_phase3 valide trouvé.')
    print('Backups examinés:', len(backups))
    raise SystemExit(2)

# Identifier la fonction rpLoadFeed dans le script principal valide du backup.
backup_feed_match=re.search(r'(?:async\s+)?function\s+rpLoadFeed\s*\([^)]*\)\s*\{', valid_html)
if not backup_feed_match:
    raise SystemExit('ERREUR: rpLoadFeed introuvable dans le backup valide.')
backup_script_close=valid_html.find('</script>', backup_feed_match.start())
if backup_script_close < 0:
    raise SystemExit('ERREUR: fin du script principal introuvable dans le backup.')
backup_tail=valid_html[backup_feed_match.start():backup_script_close]

# Remplacer seulement la fin cassée du script principal actuel à partir de rpLoadFeed.
current_feed_match=re.search(r'(?:async\s+)?function\s+rpLoadFeed\s*\([^)]*\)\s*\{', current)
if not current_feed_match:
    raise SystemExit('ERREUR: rpLoadFeed actuel introuvable.')
current_script_close=current.find('</script>', current_feed_match.start())
if current_script_close < 0:
    raise SystemExit('ERREUR: fin du script principal actuel introuvable.')

candidate=current[:current_feed_match.start()] + backup_tail + current[current_script_close:]

# Le script principal doit redevenir entièrement valide AVANT de remettre le feed enrichi.
errors=check_html(candidate)
if errors:
    print('ERREUR: restaurer la fin du script depuis le backup ne suffit pas. Aucun fichier modifié.')
    for idx,line,detail in errors[:3]:
        print(f'Bloc #{idx} vers ligne HTML {line}:')
        print(detail)
    raise SystemExit(3)

# Ajouter le feed enrichi comme override séparé. Ainsi on ne découpe plus la fonction historique.
override_marker='/* RunPacer safe social feed override */'
if override_marker not in candidate:
    override=r'''
<script>
/* RunPacer safe social feed override */
window.rpLoadFeed = async function(friendIds) {
    const supa = (typeof rpSupa !== 'undefined' && rpSupa)
      || (typeof window.rpGetSupabaseClient === 'function' ? window.rpGetSupabaseClient() : null);
    if (!supa || !friendIds?.length) return;
    const feedEl=document.getElementById('rp-feed-list');
    if (!feedEl) return;
    const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

    const { data:runs, error:runError }=await supa.from('runs')
      .select('*, profiles(username,avatar,xp_level,xp_grade)')
      .in('profile_id',friendIds)
      .order('created_at',{ascending:false})
      .limit(20);
    if (runError) {
      console.warn('[RunPacer Social] feed',runError);
      return;
    }
    if (!runs?.length) {
      feedEl.innerHTML='<div style="text-align:center;padding:20px;color:var(--muted-color);font-size:13px;">Aucune course récente de tes amis</div>';
      return;
    }

    const ids=runs.map(r=>r.id);
    const [{data:likes},{data:comments}]=await Promise.all([
      supa.from('run_likes').select('run_id,profile_id').in('run_id',ids),
      supa.from('run_comments').select('run_id,id').in('run_id',ids)
    ]);
    const likeCounts=new Map(), commentCounts=new Map(), myLikes=new Set();
    (likes||[]).forEach(l=>{
      likeCounts.set(l.run_id,(likeCounts.get(l.run_id)||0)+1);
      if (l.profile_id===window.rpMyProfile?.id || (typeof rpMyProfile!=='undefined' && l.profile_id===rpMyProfile?.id)) myLikes.add(l.run_id);
    });
    (comments||[]).forEach(c=>commentCounts.set(c.run_id,(commentCounts.get(c.run_id)||0)+1));

    feedEl.innerHTML=runs.map(r=>{
      const mins=r.duration_secs?Math.floor(r.duration_secs/60):null;
      const dur=mins?`${mins} min`:'';
      const liked=myLikes.has(r.id);
      return `<div class="rp-run-card" data-run-id="${r.id}">
        <div class="rp-run-top">
          <span class="rp-run-avatar">${esc(r.profiles?.avatar||'🏃')}</span>
          <span class="rp-run-who">@${esc(r.profiles?.username||'?')}</span>
          <span style="font-size:10px;color:var(--muted-color);">Niv. ${Number(r.profiles?.xp_level||1)}</span>
          <span class="rp-run-date">${esc(r.date||'')}</span>
        </div>
        <div class="rp-run-stats">
          <span class="rp-run-stat">📍 <strong>${parseFloat(r.distance_km).toFixed(2)} km</strong></span>
          ${dur?`<span class="rp-run-stat">⏱ <strong>${dur}</strong></span>`:''}
          <span class="rp-run-stat">🏷 ${esc(r.name||'Course')}</span>
        </div>
        <div style="display:flex;gap:8px;margin-top:9px;">
          <button class="btn btn-ghost" style="padding:5px 9px;font-size:12px;" data-like-run="${r.id}" onclick="rpToggleRunLike('${r.id}',this)">${liked?'❤️':'♡'} <span data-like-count="${r.id}">${likeCounts.get(r.id)||0}</span></button>
          <button class="btn btn-ghost" style="padding:5px 9px;font-size:12px;" onclick="rpToggleRunComments('${r.id}')">💬 <span data-comment-count="${r.id}">${commentCounts.get(r.id)||0}</span></button>
        </div>
        <div id="rp-comments-${r.id}" style="display:none;margin-top:9px;border-top:1px solid var(--surface-alt2-color);padding-top:8px;"></div>
      </div>`;
    }).join('');
};
try { rpLoadFeed = window.rpLoadFeed; } catch (_) {}
</script>
'''
    if '</body>' not in candidate:
        raise SystemExit('ERREUR: </body> introuvable.')
    candidate=candidate.replace('</body>',override+'\n</body>',1)

# Validation de TOUS les scripts après restauration + override.
errors=check_html(candidate)
if errors:
    print('ERREUR: la version finale reste invalide. Aucun fichier modifié.')
    for idx,line,detail in errors[:5]:
        print(f'Bloc #{idx} vers ligne HTML {line}:')
        print(detail)
    raise SystemExit(4)

stamp=datetime.now().strftime('%Y%m%d_%H%M%S')
backup_current=path.with_name(f'index.html.backup_before_feed_recovery_{stamp}')
shutil.copy2(path,backup_current)
path.write_text(candidate,encoding='utf-8')

print('Réparation structurelle appliquée.')
print('- backup valide utilisé:', valid_backup.name)
print('- fin historique de rpLoadFeed restaurée')
print('- nouveau feed social déplacé dans un override séparé')
print('- TOUS les blocs JavaScript: node --check OK')
print('Backup de sécurité:',backup_current)
print('Aucune donnée utilisateur ou Supabase n’a été supprimée.')
PY
