import type { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../../_lib/supabase';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const bossId = req.query.id as string;
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }
  const { km, seconds, userId, clanId, source, runId } = req.body || {};
  if (typeof km !== 'number' || km <= 0 || km > 100 || typeof seconds !== 'number' || seconds <= 0) {
    res.status(400).json({ error: 'invalid distance or time' });
    return;
  }
  const speed = km / (seconds / 3600);
  if (speed > 25) {
    res.status(400).json({ error: 'speed too high' });
    return;
  }
  const { error } = await supabase.from('boss_contribution').upsert({
    boss_id: bossId,
    run_id: runId,
    user_id: userId,
    clan_id: clanId,
    km,
    seconds,
    source,
  }, { onConflict: 'boss_id,run_id,user_id' });
  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }
  res.json({ ok: true });
}
