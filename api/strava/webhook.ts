import type { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../_lib/supabase';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method === 'GET') {
    const challenge = req.query['hub.challenge'];
    res.json({ 'hub.challenge': challenge });
    return;
  }
  if (req.method === 'POST') {
    const event = req.body;
    // Implement retrieval of activity via Strava API if needed
    // For demo, just log and acknowledge
    console.log('Strava webhook event', event?.object_id);
    res.json({ ok: true });
    return;
  }
  res.status(405).end();
}
