import type { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../_lib/supabase';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const now = new Date().toISOString();
  await supabase.from('boss_event').update({ status: 'active' }).lte('start_time', now).eq('status', 'scheduled');

  const { data: active } = await supabase
    .from('boss_event')
    .select('id,end_time,hp_total')
    .eq('status', 'active');
  if (active) {
    for (const b of active) {
      const { data: hp } = await supabase
        .from('boss_hp')
        .select('hp_remaining')
        .eq('boss_id', b.id)
        .single();
      const hpRemaining = hp?.hp_remaining ?? b.hp_total;
      if (hpRemaining <= 0) {
        await supabase.from('boss_event').update({ status: 'defeated' }).eq('id', b.id);
        // Award badge to participants via stored procedure if available
        await supabase.rpc('award_boss_badge', { boss_id: b.id }).catch(() => {});
      } else if (new Date(b.end_time).getTime() <= Date.now()) {
        await supabase.from('boss_event').update({ status: 'expired' }).eq('id', b.id);
      }
    }
  }
  res.json({ ok: true });
}
