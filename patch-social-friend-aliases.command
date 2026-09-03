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
backup = path.with_name(f'index.html.backup_friendaliases_{stamp}')
shutil.copy2(path, backup)
changes=[]

old = "profiles!profile_id_a(id,username,avatar,badges,xp_level,xp_grade,total_xp,total_km,recent_runs), profiles!profile_id_b(id,username,avatar,badges,xp_level,xp_grade,total_xp,total_km,recent_runs)"
new = "a:profiles!profile_id_a(id,username,avatar,badges,xp_level,xp_grade,total_xp,total_km,recent_runs), b:profiles!profile_id_b(id,username,avatar,badges,xp_level,xp_grade,total_xp,total_km,recent_runs)"
if old in text:
    text=text.replace(old,new,1); changes.append('friend-query-aliases')
elif new not in text:
    raise SystemExit('ERREUR: requête amis progression non reconnue.')

old_map = "f.profile_id_a === myId ? f['profiles!profile_id_b'] : f['profiles!profile_id_a']"
new_map = "f.profile_id_a === myId ? f.b : f.a"
count=text.count(old_map)
if count:
    text=text.replace(old_map,new_map); changes.append(f'friend-map-aliases({count})')
elif new_map not in text:
    raise SystemExit('ERREUR: mapping des amis non reconnu.')

# Boss Run invite modal uses a smaller friends select: alias it too.
old2 = "profiles!profile_id_a(id,username,avatar), profiles!profile_id_b(id,username,avatar)"
new2 = "a:profiles!profile_id_a(id,username,avatar), b:profiles!profile_id_b(id,username,avatar)"
if old2 in text:
    text=text.replace(old2,new2,1); changes.append('boss-friend-query-aliases')

# If the small-query mapping still exists after the global replacement, normalize it.
text=text.replace("f.profile_id_a === myId ? f['profiles!profile_id_b'] : f['profiles!profile_id_a']", new_map)

# Ensure the feed receives the actual friend profile ids once accepted friends are loaded.
needle = "const friendProfiles = friends.map(f =>\n                f.profile_id_a === myId ? f.b : f.a\n            ).filter(Boolean);"
if needle in text:
    repl = needle + "\n\n            // Charger le feed social à partir des mêmes profils acceptés.\n            rpLoadFeed(friendProfiles.map(p => p.id));"
    text=text.replace(needle,repl,1); changes.append('feed-from-accepted-friends')
elif "rpLoadFeed(friendProfiles.map(p => p.id))" not in text:
    raise SystemExit('ERREUR: point de chargement du feed non reconnu.')

# Avoid treating an already accepted relation as a failed new request.
old_send = "const { error } = await rpSupa.from('friendships').insert({\n                profile_id_a: rpMyProfile.id, profile_id_b: toId, status: 'pending'\n            });"
new_send = "const { data: existingRel } = await rpSupa.from('friendships')\n                .select('id,status')\n                .or(`and(profile_id_a.eq.${rpMyProfile.id},profile_id_b.eq.${toId}),and(profile_id_a.eq.${toId},profile_id_b.eq.${rpMyProfile.id})`)\n                .maybeSingle();\n            if (existingRel) {\n                const resEl = document.getElementById('rp-search-result');\n                if (resEl) resEl.innerHTML = existingRel.status === 'accepted'\n                    ? `<span style=\"font-size:13px;color:var(--secondary-color)\">✓ @${toName} est déjà ton ami.</span>`\n                    : `<span style=\"font-size:13px;color:var(--muted-color)\">Demande déjà en attente.</span>`;\n                return;\n            }\n            const { error } = await rpSupa.from('friendships').insert({\n                profile_id_a: rpMyProfile.id, profile_id_b: toId, status: 'pending'\n            });"
if old_send in text:
    text=text.replace(old_send,new_send,1); changes.append('existing-friend-guard')
elif "existingRel.status === 'accepted'" not in text:
    raise SystemExit('ERREUR: envoi demande ami non reconnu.')

path.write_text(text,encoding='utf-8')
print('Patch alias amis appliqué.')
for c in changes: print('-',c)
print('Backup:',backup)
print('Aucune relation ni course Supabase n\'a été supprimée.')
PY
