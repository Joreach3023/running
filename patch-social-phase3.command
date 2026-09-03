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
backup = path.with_name(f'index.html.backup_social_phase3_{stamp}')
shutil.copy2(path, backup)
changes=[]


def function_span(src, pattern):
    m = re.search(pattern, src)
    if not m:
        return None
    brace = src.find('{', m.start())
    if brace < 0:
        return None
    i=brace; depth=0; quote=None; esc=False; line_comment=False; block_comment=False
    while i < len(src):
        c=src[i]; n=src[i+1] if i+1 < len(src) else ''
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
                    return (m.start(), brace, i, end)
        i+=1
    return None


def replace_function(src, pattern, replacement):
    span=function_span(src, pattern)
    if not span:
        return src, False
    start, _, _, end=span
    return src[:start] + replacement + src[end:], True

# -----------------------------------------------------------------------------
# 1) Friend-card Boss Run invite = exact clicked friend + already-member guard.
# -----------------------------------------------------------------------------
old_click = "onclick=\"rpInviteToBossRun('${p.id}','${p.username}')\""
new_click = "onclick=\"rpInviteToBossRun('${p.id}','${p.username}',this)\""
if old_click in text:
    text=text.replace(old_click,new_click,1)
    changes.append('friend-invite-passes-button')

invite_fn = r'''window.rpInviteToBossRun = async function(profileId, username, btn) {
            const supa = (typeof rpSupa !== 'undefined' && rpSupa)
                || (typeof brSupa !== 'undefined' && brSupa)
                || (typeof window.rpGetSupabaseClient === 'function' ? window.rpGetSupabaseClient() : null);
            if (!supa) return;

            const previous = btn?.innerHTML || '';
            if (btn) { btn.disabled = true; btn.textContent = 'Vérification…'; }

            const toast = (message, ok=true) => {
                let el = document.getElementById('rp-social-toast');
                if (!el) {
                    el=document.createElement('div'); el.id='rp-social-toast';
                    el.style.cssText='position:fixed;left:16px;right:16px;bottom:calc(84px + env(safe-area-inset-bottom));z-index:99999;padding:12px 14px;border-radius:12px;background:var(--surface-color,#1d1d1f);box-shadow:0 8px 30px rgba(0,0,0,.3);font-size:13px;font-weight:600;text-align:center;';
                    document.body.appendChild(el);
                }
                el.style.color=ok?'var(--secondary-color,#34c759)':'var(--warning-color,#ff9f0a)';
                el.textContent=message; el.style.display='block';
                clearTimeout(window.__rpSocialToastTimer);
                window.__rpSocialToastTimer=setTimeout(()=>el.style.display='none',2800);
            };

            try {
                let me = (typeof rpMyProfile !== 'undefined') ? rpMyProfile : null;
                if (!me?.id) {
                    const dev=localStorage.getItem('rp_device_id');
                    const { data }=await supa.from('profiles').select('id,username,avatar').eq('device_id',dev).single();
                    me=data;
                    if (typeof rpMyProfile !== 'undefined' && data) rpMyProfile=data;
                }
                if (!me?.id) throw new Error('Ton profil social est introuvable.');

                let run=null;
                if (typeof brRunId !== 'undefined' && brRunId) {
                    const { data }=await supa.from('boss_runs').select('id,code,boss_name,event_name,status,created_at').eq('id',brRunId).maybeSingle();
                    if (data?.status==='active') run=data;
                }
                if (!run && typeof brRunCode !== 'undefined' && brRunCode) {
                    const { data }=await supa.from('boss_runs').select('id,code,boss_name,event_name,status,created_at').eq('code',brRunCode).maybeSingle();
                    if (data?.status==='active') run=data;
                }
                if (!run) {
                    const { data: memberships }=await supa.from('br_members').select('run_id,joined_at').eq('profile_id',me.id).order('joined_at',{ascending:false}).limit(30);
                    const ids=[...new Set((memberships||[]).map(m=>m.run_id).filter(Boolean))];
                    if (ids.length) {
                        const { data: activeRuns }=await supa.from('boss_runs').select('id,code,boss_name,event_name,status,created_at').in('id',ids).eq('status','active').order('created_at',{ascending:false}).limit(1);
                        run=activeRuns?.[0]||null;
                    }
                }
                if (!run) throw new Error('Aucune Boss Run active trouvée.');

                const { data: member }=await supa.from('br_members').select('id').eq('run_id',run.id).eq('profile_id',profileId).limit(1);
                if (member?.length) {
                    if (btn) { btn.disabled=true; btn.innerHTML='✓ Dans l\'escouade'; }
                    toast(`@${username} est déjà dans cette Boss Run.`);
                    return;
                }

                const { data: pending }=await supa.from('rp_invites').select('id').eq('type','bossrun').eq('run_id',run.id).eq('to_profile_id',profileId).eq('status','pending').limit(1);
                if (pending?.length) {
                    if (btn) { btn.disabled=true; btn.innerHTML='✓ Invitation envoyée'; }
                    toast(`Invitation déjà envoyée à @${username}.`);
                    return;
                }

                const { error }=await supa.from('rp_invites').insert({
                    type:'bossrun', from_key:me.id, to_key:profileId,
                    from_profile_id:me.id, to_profile_id:profileId, run_id:run.id,
                    message:`@${me.username||'Un coureur'} t’invite à ${run.event_name||run.boss_name||'une Boss Run'} · code ${run.code}`,
                    status:'pending'
                });
                if (error) throw error;

                if (btn) { btn.disabled=true; btn.innerHTML='✓ Invitation envoyée'; }
                toast(`Invitation envoyée à @${username}.`);
            } catch(e) {
                console.warn('[RunPacer Social] invitation Boss Run',e);
                if (btn) { btn.disabled=false; btn.innerHTML=previous||'Inviter'; }
                toast(e?.message||`Impossible d’inviter @${username}`,false);
            }
        };'''
text,ok=replace_function(text,r"window\.rpInviteToBossRun\s*=\s*(?:async\s+)?function\s*\([^)]*\)\s*\{",invite_fn)
if not ok:
    raise SystemExit('ERREUR: fonction rpInviteToBossRun introuvable.')
changes.append('direct-invite-with-membership-guard')

# -----------------------------------------------------------------------------
# 2) Boss Run inbox without PostgREST nested joins (robust on Cath's device).
# -----------------------------------------------------------------------------
inbox_fn = r'''window.rpLoadBossInvites = async function(){
    if (typeof rpMyProfile === 'undefined' || !rpMyProfile?.id) return;
    const supa = (typeof rpSupa !== 'undefined' && rpSupa)
      || (typeof window.rpGetSupabaseClient === 'function' ? window.rpGetSupabaseClient() : null);
    if (!supa) return;

    const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    let card=document.getElementById('rp-boss-invites-card');
    if (!card) {
      const anchor=document.getElementById('rp-requests-card') || document.getElementById('rp-my-profile-card');
      if (!anchor) return;
      anchor.insertAdjacentHTML('afterend','<div class="card" id="rp-boss-invites-card" style="display:none;"><div class="card-title">⚔️ Invitations Boss Run</div><div id="rp-boss-invites-list"></div></div>');
      card=document.getElementById('rp-boss-invites-card');
    }
    const list=document.getElementById('rp-boss-invites-list');

    const { data: invites, error }=await supa.from('rp_invites')
      .select('id,run_id,message,created_at,expires_at,from_profile_id')
      .eq('type','bossrun').eq('to_profile_id',rpMyProfile.id).eq('status','pending')
      .order('created_at',{ascending:false});
    if (error) { console.warn('[BossRun] inbox',error); card.style.display='none'; return; }
    const activeInvites=(invites||[]).filter(i => !i.expires_at || new Date(i.expires_at) > new Date());
    if (!activeInvites.length) { card.style.display='none'; return; }

    const senderIds=[...new Set(activeInvites.map(i=>i.from_profile_id).filter(Boolean))];
    const runIds=[...new Set(activeInvites.map(i=>i.run_id).filter(Boolean))];
    const [{data:senders},{data:runs}]=await Promise.all([
      senderIds.length ? supa.from('profiles').select('id,username,avatar').in('id',senderIds) : Promise.resolve({data:[]}),
      runIds.length ? supa.from('boss_runs').select('id,code,boss_name,event_name,status,ends_at').in('id',runIds) : Promise.resolve({data:[]})
    ]);
    const senderMap=new Map((senders||[]).map(x=>[x.id,x]));
    const runMap=new Map((runs||[]).map(x=>[x.id,x]));

    card.style.display='block';
    list.innerHTML=activeInvites.map(i=>{
      const from=senderMap.get(i.from_profile_id)||{};
      const run=runMap.get(i.run_id)||{};
      const inactive=run.status && run.status!=='active';
      return `<div class="rp-friend-card" style="align-items:center;gap:10px;">
        <span class="rp-friend-avatar">${esc(from.avatar||'🏃')}</span>
        <div class="rp-friend-info" style="flex:1;min-width:0;">
          <div class="rp-friend-name">@${esc(from.username||'coureur')}</div>
          <div class="rp-friend-sub">${esc(run.event_name||run.boss_name||'Boss Run')} · code ${esc(run.code||'')}${inactive?' · terminée':''}</div>
        </div>
        <button class="btn btn-primary" style="padding:5px 9px;font-size:11px;" onclick="rpAcceptBossInvite('${i.id}','${i.run_id}')" ${inactive?'disabled':''}>Accepter</button>
        <button class="btn btn-ghost" style="padding:5px 8px;font-size:11px;" onclick="rpDeclineBossInvite('${i.id}')">✕</button>
      </div>`;
    }).join('');
  };'''
text,ok=replace_function(text,r"window\.rpLoadBossInvites\s*=\s*(?:async\s+)?function\s*\([^)]*\)\s*\{",inbox_fn)
if not ok:
    raise SystemExit('ERREUR: fonction rpLoadBossInvites introuvable. Exécute d’abord patch-bossrun-social-invites.command.')
changes.append('robust-boss-invite-inbox')

# -----------------------------------------------------------------------------
# 3) Every completed RunPacer run contributes to ALL active Boss Runs joined.
#    Existing single-run logic remains; br_activities prevents double credit.
# -----------------------------------------------------------------------------
multi_marker='/* RunPacer multi Boss Run propagation */'
if multi_marker not in text:
    span=function_span(text,r"window\.rpSaveRunToSupabase\s*=\s*(?:async\s+)?function\s*\([^)]*\)\s*\{")
    if not span:
        raise SystemExit('ERREUR: fonction rpSaveRunToSupabase introuvable.')
    _,_,close,_=span
    inject=r'''

            /* RunPacer multi Boss Run propagation */
            try {
                if (saved?.id && km > 0 && rpMyProfile?.id) {
                    const activityKey = 'rp_' + saved.id;
                    const { data: memberships } = await rpSupa.from('br_members')
                        .select('id,run_id,km,dmg')
                        .eq('profile_id', rpMyProfile.id);
                    const memberRows = memberships || [];
                    const runIds = [...new Set(memberRows.map(m => m.run_id).filter(Boolean))];
                    if (runIds.length) {
                        const { data: activeRuns } = await rpSupa.from('boss_runs')
                            .select('id,hp_current,status')
                            .in('id', runIds)
                            .eq('status','active');
                        const activeMap = new Map((activeRuns || []).map(r => [r.id, r]));
                        const activeIds = [...activeMap.keys()];
                        let credited = new Set();
                        if (activeIds.length) {
                            const { data: existingActs } = await rpSupa.from('br_activities')
                                .select('run_id')
                                .eq('strava_activity_id', activityKey)
                                .in('run_id', activeIds);
                            credited = new Set((existingActs || []).map(a => a.run_id));
                        }
                        for (const member of memberRows) {
                            if (!activeMap.has(member.run_id) || credited.has(member.run_id)) continue;
                            const { error: actErr } = await rpSupa.from('br_activities').insert({
                                run_id: member.run_id,
                                member_id: member.id,
                                strava_activity_id: activityKey,
                                km,
                                activity_type: runData.type || 'Run'
                            });
                            if (actErr && actErr.code !== '23505') {
                                console.warn('[BossRun] activité multi-run', actErr);
                                continue;
                            }
                            if (actErr?.code === '23505') continue;

                            const newKm = (parseFloat(member.km) || 0) + km;
                            await rpSupa.from('br_members').update({ km:newKm, dmg:newKm }).eq('id',member.id);
                            const run = activeMap.get(member.run_id);
                            const newHp = Math.max(0,(parseFloat(run?.hp_current)||0)-km);
                            await rpSupa.from('boss_runs').update({ hp_current:newHp }).eq('id',member.run_id);
                            run.hp_current = newHp;
                        }
                    }
                }
            } catch (multiErr) {
                console.warn('[BossRun] propagation multi-run', multiErr);
            }
'''
    text=text[:close] + inject + text[close:]
    changes.append('all-active-boss-runs-get-credit')

# -----------------------------------------------------------------------------
# 4) Replace friend run feed with likes + comments.
# -----------------------------------------------------------------------------
feed_fn=r'''async function rpLoadFeed(friendIds) {
            if (!rpSupa || !friendIds?.length) return;
            const feedEl=document.getElementById('rp-feed-list');
            if (!feedEl) return;
            const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

            const { data:runs }=await rpSupa.from('runs')
                .select('*, profiles(username,avatar,xp_level,xp_grade)')
                .in('profile_id',friendIds)
                .order('created_at',{ascending:false})
                .limit(20);
            if (!runs?.length) {
                feedEl.innerHTML='<div style="text-align:center;padding:20px;color:var(--muted-color);font-size:13px;">Aucune course récente de tes amis</div>';
                return;
            }

            const ids=runs.map(r=>r.id);
            const [{data:likes},{data:comments}]=await Promise.all([
                rpSupa.from('run_likes').select('run_id,profile_id').in('run_id',ids),
                rpSupa.from('run_comments').select('run_id,id').in('run_id',ids)
            ]);
            const likeCounts=new Map(), commentCounts=new Map(), myLikes=new Set();
            (likes||[]).forEach(l=>{ likeCounts.set(l.run_id,(likeCounts.get(l.run_id)||0)+1); if (l.profile_id===rpMyProfile?.id) myLikes.add(l.run_id); });
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
        }'''
text,ok=replace_function(text,r"(?:async\s+)?function\s+rpLoadFeed\s*\([^)]*\)\s*\{",feed_fn)
if not ok:
    raise SystemExit('ERREUR: fonction rpLoadFeed introuvable.')
changes.append('run-feed-likes-comments')

# Social interaction helpers.
helper_marker='/* RunPacer run reactions helpers */'
if helper_marker not in text:
    helpers=r'''
<script>
/* RunPacer run reactions helpers */
(function(){
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const sb=()=> (typeof rpSupa!=='undefined'&&rpSupa) || (typeof window.rpGetSupabaseClient==='function'?window.rpGetSupabaseClient():null);

  window.rpRefreshRunReactionCounts=async function(runId){
    const supa=sb(); if(!supa)return;
    const [{count:likes},{count:comments},{data:mine}]=await Promise.all([
      supa.from('run_likes').select('*',{count:'exact',head:true}).eq('run_id',runId),
      supa.from('run_comments').select('*',{count:'exact',head:true}).eq('run_id',runId),
      rpMyProfile?.id ? supa.from('run_likes').select('id').eq('run_id',runId).eq('profile_id',rpMyProfile.id).limit(1) : Promise.resolve({data:[]})
    ]);
    document.querySelectorAll(`[data-like-count="${runId}"]`).forEach(x=>x.textContent=likes||0);
    document.querySelectorAll(`[data-comment-count="${runId}"]`).forEach(x=>x.textContent=comments||0);
    document.querySelectorAll(`[data-like-run="${runId}"]`).forEach(x=>{ x.childNodes[0].textContent=(mine?.length?'❤️ ':'♡ '); });
  };

  window.rpToggleRunLike=async function(runId,btn){
    const supa=sb(); if(!supa||!rpMyProfile?.id)return;
    if(btn)btn.disabled=true;
    try{
      const {data:existing}=await supa.from('run_likes').select('id').eq('run_id',runId).eq('profile_id',rpMyProfile.id).limit(1);
      if(existing?.length) await supa.from('run_likes').delete().eq('id',existing[0].id);
      else await supa.from('run_likes').insert({run_id:runId,profile_id:rpMyProfile.id});
      await rpRefreshRunReactionCounts(runId);
    }finally{ if(btn)btn.disabled=false; }
  };

  window.rpToggleRunComments=async function(runId){
    const panel=document.getElementById('rp-comments-'+runId); if(!panel)return;
    if(panel.style.display==='none'||!panel.style.display){ panel.style.display='block'; await rpLoadRunComments(runId); }
    else panel.style.display='none';
  };

  window.rpLoadRunComments=async function(runId){
    const supa=sb(); const panel=document.getElementById('rp-comments-'+runId); if(!supa||!panel)return;
    panel.innerHTML='<div style="font-size:12px;color:var(--muted-color);">Chargement…</div>';
    const {data,error}=await supa.from('run_comments').select('id,message,created_at,profile_id,profiles(username,avatar)').eq('run_id',runId).order('created_at',{ascending:true}).limit(50);
    if(error){panel.innerHTML='<div style="font-size:12px;color:var(--warning-color);">Impossible de charger les commentaires.</div>';return;}
    const rows=(data||[]).map(c=>`<div style="display:flex;gap:7px;margin:6px 0;font-size:12px;"><span>${esc(c.profiles?.avatar||'🏃')}</span><div><strong>@${esc(c.profiles?.username||'?')}</strong> ${esc(c.message)}</div></div>`).join('');
    panel.innerHTML=`${rows||'<div style="font-size:12px;color:var(--muted-color);margin-bottom:6px;">Aucun commentaire</div>'}
      <div style="display:flex;gap:6px;margin-top:8px;">
        <input id="rp-comment-input-${runId}" maxlength="280" placeholder="Écrire un commentaire…" style="flex:1;min-width:0;padding:8px 9px;border-radius:8px;border:1px solid var(--surface-alt2-color);background:var(--background-color);color:var(--text-color);font-size:12px;">
        <button class="btn btn-primary" style="padding:6px 10px;font-size:11px;" onclick="rpAddRunComment('${runId}')">Envoyer</button>
      </div>`;
  };

  window.rpAddRunComment=async function(runId){
    const supa=sb(); const input=document.getElementById('rp-comment-input-'+runId); if(!supa||!input||!rpMyProfile?.id)return;
    const message=input.value.trim(); if(!message)return;
    input.disabled=true;
    try{
      const {error}=await supa.from('run_comments').insert({run_id:runId,profile_id:rpMyProfile.id,message:message.slice(0,280)});
      if(error)throw error;
      input.value=''; await rpLoadRunComments(runId); await rpRefreshRunReactionCounts(runId);
    }catch(e){console.warn('[RunPacer Social] commentaire',e);}
    finally{input.disabled=false;}
  };

  // Inbox refresh independent of the friend-loader implementation.
  let lastInbox=0;
  const refreshInbox=()=>{
    const card=document.getElementById('rp-my-profile-card');
    if(!card||card.offsetParent===null||typeof rpLoadBossInvites!=='function')return;
    const now=Date.now(); if(now-lastInbox<2500)return; lastInbox=now;
    rpLoadBossInvites();
  };
  new MutationObserver(refreshInbox).observe(document.body,{subtree:true,childList:true,attributes:true,attributeFilter:['style','class']});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)refreshInbox();});
  setTimeout(refreshInbox,600);
})();
</script>
'''
    if '</body>' not in text:
        raise SystemExit('ERREUR: </body> introuvable.')
    text=text.replace('</body>',helpers+'\n</body>',1)
    changes.append('reaction-actions-and-inbox-refresh')

path.write_text(text,encoding='utf-8')
print('Patch social phase 3 appliqué.')
for c in changes: print('-',c)
print('Backup:',backup)
print('Ajouts: inbox Boss Run robuste, garde déjà-membre, multi-Boss Run, likes et commentaires.')
print('Aucune donnée locale ou Supabase existante n\'a été supprimée.')
PY
