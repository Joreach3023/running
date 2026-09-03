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
backup = path.with_name(f'index.html.backup_bossinvites_{stamp}')
shutil.copy2(path, backup)
changes=[]

# Replace one window.fn = function(...) {...} block using brace matching.
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

# 1) Real Boss Run invite: create rp_invites row before showing "Envoyé".
replacement = r'''window.brInviteFriend = async function(profileId, username, btn) {
            if (!brRunCode) return;
            const supa = (typeof brSupa !== 'undefined' && brSupa) || (typeof rpSupa !== 'undefined' && rpSupa) || (typeof window.rpGetSupabaseClient === 'function' ? window.rpGetSupabaseClient() : null);
            if (!supa) return;

            const oldHtml = btn?.innerHTML || '';
            if (btn) { btn.disabled = true; btn.textContent = 'Envoi…'; }
            try {
                let me = (typeof rpMyProfile !== 'undefined') ? rpMyProfile : null;
                if (!me?.id) {
                    const dev = localStorage.getItem('rp_device_id');
                    const { data } = await supa.from('profiles').select('id,username,avatar').eq('device_id', dev).single();
                    me = data;
                    if (typeof rpMyProfile !== 'undefined' && data) rpMyProfile = data;
                }
                if (!me?.id) throw new Error('Profil RunPacer introuvable.');

                let run = null;
                if (typeof brRunId !== 'undefined' && brRunId) {
                    const { data } = await supa.from('boss_runs').select('id,code,boss_name,event_name,status').eq('id', brRunId).single();
                    run = data;
                }
                if (!run) {
                    const { data } = await supa.from('boss_runs').select('id,code,boss_name,event_name,status').eq('code', brRunCode).single();
                    run = data;
                }
                if (!run?.id) throw new Error('Boss Run introuvable.');

                const { data: existing } = await supa.from('rp_invites')
                    .select('id')
                    .eq('type','bossrun')
                    .eq('to_profile_id', profileId)
                    .eq('run_id', run.id)
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
            } catch (e) {
                console.warn('[BossRun] invitation échouée', e);
                if (btn) { btn.disabled = false; btn.innerHTML = oldHtml || 'Réessayer'; }
            }
        };'''
text, ok = replace_window_function(text, 'brInviteFriend', replacement)
if not ok and "invitation échouée" not in text:
    raise SystemExit('ERREUR: fonction brInviteFriend non reconnue.')
if ok: changes.append('real-bossrun-invite')

# 2) Make new Boss Run members carry the canonical profile_id + username.
old = "run_id: run.id, name, avatar: avatars[Math.floor(Math.random()*avatars.length)],"
new = "run_id: run.id, profile_id: (typeof rpMyProfile !== 'undefined' && rpMyProfile?.id) ? rpMyProfile.id : null, name: (typeof rpMyProfile !== 'undefined' && rpMyProfile?.username) ? rpMyProfile.username : name, avatar: (typeof rpMyProfile !== 'undefined' && rpMyProfile?.avatar) ? rpMyProfile.avatar : avatars[Math.floor(Math.random()*avatars.length)],"
if old in text:
    text=text.replace(old,new,1); changes.append('joined-member-profile-id')
elif 'profile_id: (typeof rpMyProfile' not in text:
    raise SystemExit('ERREUR: insertion membre Boss Run non reconnue.')

old2 = "run_id: runId,\n                        name:   userData?.firstName || 'Moi',"
new2 = "run_id: runId,\n                        profile_id: (typeof rpMyProfile !== 'undefined' && rpMyProfile?.id) ? rpMyProfile.id : null,\n                        name:   (typeof rpMyProfile !== 'undefined' && rpMyProfile?.username) ? rpMyProfile.username : (userData?.username || userData?.firstName || 'Moi'),"
if old2 in text:
    text=text.replace(old2,new2,1); changes.append('creator-profile-id')

# Include profile_id in Boss Run member reads and self detection.
text, n = re.subn(r"select\('id,name,avatar,km,dmg,device_id'\)", "select('id,name,avatar,km,dmg,device_id,profile_id')", text)
if n: changes.append('member-profile-reads')
text, n2 = re.subn(r"you:\s*m\.device_id\s*===\s*brGetDeviceId\(\)", "you: ((typeof rpMyProfile !== 'undefined' && rpMyProfile?.id && m.profile_id === rpMyProfile.id) || m.device_id === brGetDeviceId())", text)
if n2: changes.append('member-self-detection')

# 3) Inject a Boss Run invitations card + accept/decline logic in the social tab.
marker = '/* RunPacer social Boss Run invites */'
if marker not in text:
    script = r'''
<script>
/* RunPacer social Boss Run invites */
(function(){
  async function rpSocialClient(){
    if (typeof rpSupa !== 'undefined' && rpSupa) return rpSupa;
    return typeof window.rpGetSupabaseClient === 'function' ? window.rpGetSupabaseClient() : null;
  }

  window.rpLoadBossInvites = async function(){
    if (typeof rpMyProfile === 'undefined' || !rpMyProfile?.id) return;
    const supa = await rpSocialClient();
    if (!supa) return;

    let card = document.getElementById('rp-boss-invites-card');
    if (!card) {
      const anchor = document.getElementById('rp-requests-card') || document.getElementById('rp-my-profile-card');
      if (!anchor) return;
      anchor.insertAdjacentHTML('afterend', `
        <div class="card" id="rp-boss-invites-card" style="display:none;">
          <div class="card-title">⚔️ Invitations Boss Run</div>
          <div id="rp-boss-invites-list"></div>
        </div>`);
      card = document.getElementById('rp-boss-invites-card');
    }
    const list = document.getElementById('rp-boss-invites-list');
    const { data, error } = await supa.from('rp_invites')
      .select('id,run_id,message,created_at,from_profile_id,profiles!from_profile_id(username,avatar),boss_runs!run_id(code,boss_name,event_name,status,ends_at)')
      .eq('type','bossrun')
      .eq('to_profile_id', rpMyProfile.id)
      .eq('status','pending')
      .gt('expires_at', new Date().toISOString())
      .order('created_at',{ascending:false});
    if (error || !data?.length) { card.style.display='none'; return; }

    card.style.display='block';
    list.innerHTML = data.map(i => {
      const from = i.profiles || {};
      const run = i.boss_runs || {};
      return `<div class="rp-friend-card" style="align-items:center;gap:10px;">
        <span class="rp-friend-avatar">${from.avatar || '🏃'}</span>
        <div class="rp-friend-info" style="flex:1;">
          <div class="rp-friend-name">@${from.username || 'coureur'}</div>
          <div class="rp-friend-sub">${run.event_name || run.boss_name || 'Boss Run'} · code ${run.code || ''}</div>
        </div>
        <button class="btn btn-primary" style="padding:5px 9px;font-size:11px;" onclick="rpAcceptBossInvite('${i.id}','${i.run_id}')">Accepter</button>
        <button class="btn btn-ghost" style="padding:5px 8px;font-size:11px;" onclick="rpDeclineBossInvite('${i.id}')">✕</button>
      </div>`;
    }).join('');
  };

  window.rpDeclineBossInvite = async function(inviteId){
    const supa = await rpSocialClient(); if (!supa) return;
    await supa.from('rp_invites').update({status:'declined'}).eq('id',inviteId);
    rpLoadBossInvites();
  };

  window.rpAcceptBossInvite = async function(inviteId, runId){
    const supa = await rpSocialClient(); if (!supa || !rpMyProfile?.id) return;
    const { data: run } = await supa.from('boss_runs').select('*').eq('id',runId).single();
    if (!run || run.status !== 'active') {
      await supa.from('rp_invites').update({status:'expired'}).eq('id',inviteId);
      rpLoadBossInvites(); return;
    }

    const dev = localStorage.getItem('rp_device_id');
    const { data: members } = await supa.from('br_members').select('id').eq('run_id',run.id).eq('profile_id',rpMyProfile.id).limit(1);
    if (!members?.length) {
      const conn = (typeof RunpacerConnections !== 'undefined') ? RunpacerConnections.getConnections() : {};
      const { error } = await supa.from('br_members').insert({
        run_id: run.id,
        profile_id: rpMyProfile.id,
        name: rpMyProfile.username,
        avatar: rpMyProfile.avatar || '🏃',
        is_creator: false,
        device_id: dev,
        strava_access_token: conn.stravaToken || null,
        strava_refresh_token: conn.stravaRefreshToken || null,
        strava_token_expires_at: conn.stravaExpiresAt || null
      });
      if (error) { console.warn('[BossRun] accept invite', error); return; }
    }
    await supa.from('rp_invites').update({status:'accepted'}).eq('id',inviteId);

    try {
      if (typeof brJoinByCode === 'function') await brJoinByCode(run.code);
      else {
        const codeInput = document.querySelector('input[id*="code" i][id*="br" i], input[placeholder*="code" i]');
        if (codeInput) codeInput.value = run.code;
        if (typeof showSection === 'function') showSection('bossrun');
      }
    } catch (_) {}
    rpLoadBossInvites();
  };
})();
</script>
'''
    if '</body>' not in text:
        raise SystemExit('ERREUR: </body> introuvable pour injecter les invitations sociales.')
    text=text.replace('</body>',script+'\n</body>',1); changes.append('boss-invite-inbox')

# 4) Friend feed was defined but not called. Call feed + invite inbox after accepted friends resolve.
needle = ").filter(Boolean);\n\n            // Helper : rendre les badges d'un ami"
repl = ").filter(Boolean);\n\n            rpLoadFeed(friendProfiles.map(p => p.id));\n            if (typeof rpLoadBossInvites === 'function') await rpLoadBossInvites();\n\n            // Helper : rendre les badges d'un ami"
if needle in text:
    text=text.replace(needle,repl,1); changes.append('friend-feed-load')
elif 'rpLoadFeed(friendProfiles.map(p => p.id))' not in text:
    raise SystemExit('ERREUR: point de chargement du feed ami non reconnu.')

path.write_text(text, encoding='utf-8')
print('Patch Boss Run social appliqué.')
for c in changes: print('-',c)
print('Backup:',backup)
print('Aucune donnée Supabase existante n\'a été supprimée.')
PY
