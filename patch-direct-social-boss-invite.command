#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

python3 - "$INDEX" <<'PY'
import pathlib, re, shutil, sys
from datetime import datetime

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = path.with_name(f'index.html.backup_direct_bossinvite_{stamp}')
shutil.copy2(path, backup)
changes=[]

# Pass the clicked button through so the exact friend row is updated.
old_click = "onclick=\"rpInviteToBossRun('${p.id}','${p.username}')\""
new_click = "onclick=\"rpInviteToBossRun('${p.id}','${p.username}',this)\""
if old_click in text:
    text = text.replace(old_click, new_click, 1)
    changes.append('friend-button-passes-self')
elif new_click not in text:
    raise SystemExit('ERREUR: bouton Inviter de la carte ami non reconnu.')

# Robust function replacement using brace matching.
def replace_window_function(src, name, replacement):
    m = re.search(rf"window\.{re.escape(name)}\s*=\s*(?:async\s+)?function\s*\([^)]*\)\s*\{{", src)
    if not m:
        return src, False
    brace = src.find('{', m.start())
    i=brace; depth=0; quote=None; esc=False; line_comment=False; block_comment=False
    while i < len(src):
        c = src[i]; n = src[i+1] if i+1 < len(src) else ''
        if line_comment:
            if c=='\n': line_comment=False
        elif block_comment:
            if c=='*' and n=='/': block_comment=False; i+=1
        elif quote:
            if esc: esc=False
            elif c=='\\': esc=True
            elif c==quote: quote=None
        else:
            if c=='/' and n=='/': line_comment=True; i+=1
            elif c=='/' and n=='*': block_comment=True; i+=1
            elif c in "'\"`": quote=c
            elif c=='{': depth+=1
            elif c=='}':
                depth-=1
                if depth==0:
                    end=i+1
                    while end < len(src) and src[end] in ' \t': end+=1
                    if end < len(src) and src[end]==';': end+=1
                    return src[:m.start()] + replacement + src[end:], True
        i+=1
    return src, False

replacement = r'''window.rpInviteToBossRun = async function(profileId, username, btn) {
            const supa = (typeof rpSupa !== 'undefined' && rpSupa)
                || (typeof brSupa !== 'undefined' && brSupa)
                || (typeof window.rpGetSupabaseClient === 'function' ? window.rpGetSupabaseClient() : null);
            if (!supa) return;

            const previous = btn?.innerHTML || '';
            if (btn) { btn.disabled = true; btn.textContent = 'Envoi…'; }

            const showResult = (message, ok=true) => {
                let toast = document.getElementById('rp-direct-bossinvite-toast');
                if (!toast) {
                    toast = document.createElement('div');
                    toast.id = 'rp-direct-bossinvite-toast';
                    toast.style.cssText = 'position:fixed;left:16px;right:16px;bottom:calc(84px + env(safe-area-inset-bottom));z-index:99999;padding:12px 14px;border-radius:12px;background:var(--surface-color,#1d1d1f);box-shadow:0 8px 30px rgba(0,0,0,.3);font-size:13px;font-weight:600;text-align:center;';
                    document.body.appendChild(toast);
                }
                toast.style.color = ok ? 'var(--secondary-color,#34c759)' : 'var(--warning-color,#ff9f0a)';
                toast.textContent = message;
                toast.style.display = 'block';
                clearTimeout(window.__rpBossInviteToastTimer);
                window.__rpBossInviteToastTimer = setTimeout(()=>{ toast.style.display='none'; }, 2600);
            };

            try {
                let me = (typeof rpMyProfile !== 'undefined') ? rpMyProfile : null;
                if (!me?.id) {
                    const dev = localStorage.getItem('rp_device_id');
                    const { data } = await supa.from('profiles').select('id,username,avatar').eq('device_id', dev).single();
                    me = data;
                    if (typeof rpMyProfile !== 'undefined' && data) rpMyProfile = data;
                }
                if (!me?.id) throw new Error('Ton profil social est introuvable.');

                let run = null;
                if (typeof brRunId !== 'undefined' && brRunId) {
                    const { data } = await supa.from('boss_runs').select('id,code,boss_name,event_name,status,created_at').eq('id', brRunId).maybeSingle();
                    if (data?.status === 'active') run = data;
                }
                if (!run && typeof brRunCode !== 'undefined' && brRunCode) {
                    const { data } = await supa.from('boss_runs').select('id,code,boss_name,event_name,status,created_at').eq('code', brRunCode).maybeSingle();
                    if (data?.status === 'active') run = data;
                }

                if (!run) {
                    const { data: memberships } = await supa.from('br_members')
                        .select('run_id,joined_at')
                        .eq('profile_id', me.id)
                        .order('joined_at', { ascending:false })
                        .limit(20);
                    const ids = [...new Set((memberships || []).map(m => m.run_id).filter(Boolean))];
                    if (ids.length) {
                        const { data: activeRuns } = await supa.from('boss_runs')
                            .select('id,code,boss_name,event_name,status,created_at')
                            .in('id', ids)
                            .eq('status','active')
                            .order('created_at', { ascending:false })
                            .limit(1);
                        run = activeRuns?.[0] || null;
                    }
                }

                if (!run) throw new Error('Aucune Boss Run active trouvée.');

                const { data: existing } = await supa.from('rp_invites')
                    .select('id,status')
                    .eq('type','bossrun')
                    .eq('run_id',run.id)
                    .eq('to_profile_id',profileId)
                    .eq('status','pending')
                    .limit(1);

                if (!existing?.length) {
                    const { error } = await supa.from('rp_invites').insert({
                        type: 'bossrun',
                        from_key: me.id,
                        to_key: profileId,
                        from_profile_id: me.id,
                        to_profile_id: profileId,
                        run_id: run.id,
                        message: `@${me.username || 'Un coureur'} t’invite à ${run.event_name || run.boss_name || 'une Boss Run'} · code ${run.code}`,
                        status: 'pending'
                    });
                    if (error) throw error;
                }

                if (btn) {
                    btn.disabled = true;
                    btn.innerHTML = '<i data-lucide="check" style="width:13px;height:13px;"></i> Envoyé';
                    if (window.lucide) lucide.createIcons();
                }
                showResult(`Invitation envoyée à @${username}`);
            } catch (e) {
                console.warn('[RunPacer Social] invitation Boss Run', e);
                if (btn) { btn.disabled = false; btn.innerHTML = previous || 'Inviter'; }
                showResult(e?.message || `Impossible d’inviter @${username}`, false);
            }
        };'''

text, ok = replace_window_function(text, 'rpInviteToBossRun', replacement)
if ok:
    changes.append('direct-targeted-social-invite')
elif '[RunPacer Social] invitation Boss Run' not in text:
    raise SystemExit('ERREUR: fonction rpInviteToBossRun non reconnue.')

path.write_text(text, encoding='utf-8')
print('Patch invitation directe appliqué.')
for c in changes: print('-', c)
print('Backup:', backup)
print('Le bouton d’un ami invite maintenant exactement cet ami, sans ouvrir le modal générique.')
PY
