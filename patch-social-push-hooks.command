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
backup = path.with_name(f'index.html.backup_social_push_{stamp}')
shutil.copy2(path, backup)
changes=[]

marker='/* RunPacer social push bridge */'
if marker not in text:
    bridge=r'''
<script>
/* RunPacer social push bridge */
window.rpNotifySocialEvent = async function(eventType,eventId){
  if(!eventType||!eventId)return;
  const supa=(typeof rpSupa!=='undefined'&&rpSupa)
    || (typeof brSupa!=='undefined'&&brSupa)
    || (typeof window.rpGetSupabaseClient==='function'?window.rpGetSupabaseClient():null);
  if(!supa?.functions?.invoke)return;
  try{
    const {data,error}=await supa.functions.invoke('runpacer-push',{
      body:{event_type:eventType,event_id:eventId}
    });
    if(error){
      console.warn('[RunPacer Push] invoke',eventType,error);
      return;
    }
    if(data?.configured===false){
      console.info('[RunPacer Push] APNs pas encore configuré côté serveur.');
    }
  }catch(e){
    console.warn('[RunPacer Push]',eventType,e);
  }
};
</script>
'''
    if '</body>' in text:
        text=text.replace('</body>',bridge+'\n</body>',1)
    else:
        text += bridge
    changes.append('push-bridge')

old_boss="""                const { error }=await supa.from('rp_invites').insert({
                    type:'bossrun', from_key:me.id, to_key:profileId,
                    from_profile_id:me.id, to_profile_id:profileId, run_id:run.id,
                    message:`@${me.username||'Un coureur'} t’invite à ${run.event_name||run.boss_name||'une Boss Run'} · code ${run.code}`,
                    status:'pending'
                });
                if (error) throw error;
"""
new_boss="""                const { data: createdInvite, error }=await supa.from('rp_invites').insert({
                    type:'bossrun', from_key:me.id, to_key:profileId,
                    from_profile_id:me.id, to_profile_id:profileId, run_id:run.id,
                    message:`@${me.username||'Un coureur'} t’invite à ${run.event_name||run.boss_name||'une Boss Run'} · code ${run.code}`,
                    status:'pending'
                }).select('id').single();
                if (error) throw error;
                if (createdInvite?.id && typeof rpNotifySocialEvent==='function') rpNotifySocialEvent('boss_invite',createdInvite.id);
"""
if old_boss in text:
    text=text.replace(old_boss,new_boss,1); changes.append('boss-invite-push')
elif "rpNotifySocialEvent('boss_invite'" not in text:
    raise SystemExit('ERREUR: insertion Boss Run phase 3 non reconnue.')

old_like="""      if(existing?.length) await supa.from('run_likes').delete().eq('id',existing[0].id);
      else await supa.from('run_likes').insert({run_id:runId,profile_id:rpMyProfile.id});
"""
new_like="""      if(existing?.length) await supa.from('run_likes').delete().eq('id',existing[0].id);
      else {
        const {data:createdLike,error:likeError}=await supa.from('run_likes')
          .insert({run_id:runId,profile_id:rpMyProfile.id}).select('id').single();
        if(likeError) throw likeError;
        if(createdLike?.id && typeof rpNotifySocialEvent==='function') rpNotifySocialEvent('run_like',createdLike.id);
      }
"""
if old_like in text:
    text=text.replace(old_like,new_like,1); changes.append('run-like-push')
elif "rpNotifySocialEvent('run_like'" not in text:
    raise SystemExit('ERREUR: action Like phase 3 non reconnue.')

old_comment="""      const {error}=await supa.from('run_comments').insert({run_id:runId,profile_id:rpMyProfile.id,message:message.slice(0,280)});
      if(error)throw error;
"""
new_comment="""      const {data:createdComment,error}=await supa.from('run_comments')
        .insert({run_id:runId,profile_id:rpMyProfile.id,message:message.slice(0,280)}).select('id').single();
      if(error)throw error;
      if(createdComment?.id && typeof rpNotifySocialEvent==='function') rpNotifySocialEvent('run_comment',createdComment.id);
"""
if old_comment in text:
    text=text.replace(old_comment,new_comment,1); changes.append('run-comment-push')
elif "rpNotifySocialEvent('run_comment'" not in text:
    raise SystemExit('ERREUR: action Commentaire phase 3 non reconnue.')

path.write_text(text,encoding='utf-8')
print('Patch notifications sociales appliqué.')
for c in changes: print('-',c)
print('Backup:',backup)
print('Le social continue de fonctionner même si APNs n’est pas encore configuré.')
PY
