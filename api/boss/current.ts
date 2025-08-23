import type { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../_lib/supabase';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const user = req.query.user as string | undefined;
  const { data: boss, error } = await supabase
    .from('boss_event')
    .select('id,hp_total,end_time')
    .eq('status', 'active')
    .single();
  if (error || !boss) {
    res.status(404).json({ error: 'no active boss' });
    return;
  }
  const { data: hp } = await supabase
    .from('boss_hp')
    .select('hp_remaining')
    .eq('boss_id', boss.id)
    .single();
  const { data: top } = await supabase
    .from('boss_contribution')
    .select('user_id,sum(km)')
    .eq('boss_id', boss.id)
    .group('user_id')
    .order('sum', { ascending: false })
    .limit(1);
  let your = 0;
  if (user) {
    const { data: yours } = await supabase
      .from('boss_contribution')
      .select('sum(km)')
      .eq('boss_id', boss.id)
      .eq('user_id', user)
      .single();
    your = (yours && (yours as any).sum) || 0;
  }
  const hpRemaining = hp?.hp_remaining ?? boss.hp_total;
  const timeRemaining = Math.floor((new Date(boss.end_time).getTime() - Date.now()) / 1000);
  res.json({
    id: boss.id,
    hp_total: boss.hp_total,
    hp_remaining: hpRemaining,
    time_remaining: timeRemaining,
    top_contributor: top && top.length ? { user: top[0].user_id, km: (top[0] as any).sum } : null,
    your_contribution: your
  });
}
