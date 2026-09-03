#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

python3 - "$INDEX" <<'PY'
import pathlib
import re
import shutil
import sys
from datetime import datetime

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = path.with_name(f"index.html.backup_social_{stamp}")
shutil.copy2(path, backup)

changes = []

# 1) Onboarding: use one profile per device instead of blindly inserting duplicates.
old = "const { error } = await _obSupa.from('profiles').insert({ device_id:devId, auth_uid:session?.user?.id||null, username:uname, avatar:_obAv }).select().single();"
new = "const { error } = await _obSupa.from('profiles').upsert({ device_id:devId, auth_uid:session?.user?.id||null, username:uname, avatar:_obAv }, { onConflict:'device_id' }).select().single();"
if old in text:
    text = text.replace(old, new, 1)
    changes.append("onboarding-profile-upsert")
elif new not in text:
    raise SystemExit("ERREUR: création de profil onboarding non reconnue.")

# 2) Social profile editor: update existing profile; create only if none exists.
pattern = re.compile(
    r"window\.rpSaveProfile = async function\(\) \{.*?\n\s*\};\n\n\s*window\.rpEditProfile = function\(\) \{",
    re.S,
)
replacement = r'''window.rpSaveProfile = async function() {
            const username = document.getElementById('rp-username-input')?.value.trim().toLowerCase().replace(/[^a-z0-9_]/g,'');
            const errEl    = document.getElementById('rp-profile-error');
            const btn      = document.getElementById('rp-profile-save-btn');
            if (errEl) errEl.style.display = 'none';

            if (!username || username.length < 3) { rpShowProfileError('Le pseudo doit avoir au moins 3 caractères.'); return; }
            if (!rpSupa) { rpShowProfileError('Erreur de connexion.'); return; }

            btn.disabled = true; btn.textContent = rpMyProfile ? 'Enregistrement…' : 'Création…';
            try {
                const payload = { username, avatar: rpSelectedAvatar };
                let data, error;

                if (rpMyProfile?.id) {
                    ({ data, error } = await rpSupa.from('profiles')
                        .update(payload)
                        .eq('id', rpMyProfile.id)
                        .select().single());
                } else {
                    const { data: { session } } = await rpSupa.auth.getSession();
                    ({ data, error } = await rpSupa.from('profiles')
                        .upsert({ ...payload, device_id: rpDeviceId(), auth_uid: session?.user?.id || null }, { onConflict:'device_id' })
                        .select().single());
                }

                if (error) {
                    if (error.code === '23505') rpShowProfileError('Ce pseudo est déjà pris — choisis-en un autre.');
                    else rpShowProfileError(error.message);
                    return;
                }

                rpMyProfile = data;
                localStorage.setItem('runpacer_display_name', username);
                if (typeof userData === 'object' && userData) {
                    userData.username = username;
                    userData.avatar = rpSelectedAvatar;
                }
                document.getElementById('rp-profile-modal').style.display = 'none';
                rpUpdateMyProfileUI();
                rpLoadFriends();
            } catch (e) {
                rpShowProfileError(e?.message || 'Erreur de sauvegarde.');
            } finally {
                btn.disabled = false; btn.textContent = 'Enregistrer';
            }
        };

        window.rpEditProfile = function() {'''
text, count = pattern.subn(replacement, text, count=1)
if count == 1:
    changes.append("single-profile-editor")
elif "Enregistrement…" not in text:
    raise SystemExit("ERREUR: bloc rpSaveProfile non reconnu.")

# 3) Friend query: include the canonical public progression fields.
old_select = "profiles!profile_id_a(id,username,avatar,badges), profiles!profile_id_b(id,username,avatar,badges)"
new_select = "profiles!profile_id_a(id,username,avatar,badges,xp_level,xp_grade,total_xp,total_km,recent_runs), profiles!profile_id_b(id,username,avatar,badges,xp_level,xp_grade,total_xp,total_km,recent_runs)"
if old_select in text:
    text = text.replace(old_select, new_select, 1)
    changes.append("friend-progression-query")
elif new_select not in text:
    raise SystemExit("ERREUR: requête des amis non reconnue.")

# 4) Friend card: show level/grade/XP/km from the same profiles row.
needle = '<div class="rp-friend-name">@${p.username}</div>'
insert = '''<div class="rp-friend-name">@${p.username}</div>
                            <div class="rp-friend-sub">Niv. ${p.xp_level || 1} · ${p.xp_grade || 'Marcheur'} · ${Number(p.total_xp || 0).toFixed(1)} XP · ${Number(p.total_km || 0).toFixed(1)} km</div>'''
if needle in text:
    text = text.replace(needle, insert, 1)
    changes.append("friend-progression-ui")
elif "Number(p.total_xp || 0)" not in text:
    raise SystemExit("ERREUR: carte ami non reconnue.")

# 5) Own profile stats: prefer server summary so the social profile and feed agree.
old_stats = '''const runs = JSON.parse(localStorage.getItem('runPacerUserData') || '{}').runs || [];
                const totalKm = runs.reduce((s,r) => s + parseFloat(r.distance||0), 0);
                stEl.textContent = `${runs.length} course${runs.length>1?'s':''} · ${totalKm.toFixed(1)} km`;'''
new_stats = '''const recentCount = Array.isArray(rpMyProfile.recent_runs) ? rpMyProfile.recent_runs.length : 0;
                const totalKm = Number(rpMyProfile.total_km || 0);
                const level = Number(rpMyProfile.xp_level || 1);
                const grade = rpMyProfile.xp_grade || 'Marcheur';
                const xp = Number(rpMyProfile.total_xp || 0);
                stEl.textContent = `Niv. ${level} · ${grade} · ${xp.toFixed(1)} XP · ${totalKm.toFixed(1)} km${recentCount ? ` · ${recentCount} récentes` : ''}`;'''
if old_stats in text:
    text = text.replace(old_stats, new_stats, 1)
    changes.append("own-profile-server-stats")
elif "Niv. ${level}" not in text:
    raise SystemExit("ERREUR: statistiques du profil local non reconnues.")

path.write_text(text, encoding="utf-8")
print("Patch social profil appliqué.")
for c in changes:
    print("-", c)
print("Backup:", backup)
print("Aucune donnée locale ou Supabase n'a été supprimée.")
PY
