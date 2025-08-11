import { getState } from '../state/runState';
import { shouldSpeak } from './cooldown';
import { getMessage } from './messages';
import { speak } from './tts';

let timer: any;

/**
 * Starts the coaching evaluation loop.
 * The loop runs every 5 seconds and evaluates the current run state,
 * emitting voice messages when appropriate.
 */
export function startEngine(lang: 'fr' | 'en' = 'fr') {
  if (timer) return;
  const s = getState();
  speak(getMessage('start_brief', lang, s.vars), lang);

  timer = setInterval(() => {
    const st = getState();

    if (st.split_due && shouldSpeak('split', 45)) {
      speak(getMessage('split', lang, st.vars), lang);
    }

    // Pace difference
    if (st.pace_diff >= 20 && st.diff_duration >= 120 && shouldSpeak('pace_fast', 45)) {
      speak(getMessage('pace_fast', lang, st.vars), lang);
    } else if (st.pace_diff <= -20 && st.diff_duration >= 120 && shouldSpeak('pace_slow', 45)) {
      speak(getMessage('pace_slow', lang, st.vars), lang);
    }

    // Fatigue detection
    if (st.is_fatigue && shouldSpeak('fatigue', 90)) {
      speak(getMessage('fatigue', lang, st.vars), lang);
    }

    // Terrain messages
    if (st.elev_grad > 3 && shouldSpeak('hill_up', 60)) {
      speak(getMessage('hill_up', lang, st.vars), lang);
    } else if (st.elev_grad < -3 && shouldSpeak('hill_down', 60)) {
      speak(getMessage('hill_down', lang, st.vars), lang);
    }

    // Hydration reminders
    if (st.hydration_due && shouldSpeak('hydration', 600)) {
      speak(getMessage('hydration', lang, st.vars), lang);
    }

    // Final kick
    if (st.in_final_km && st.ok_for_kick && shouldSpeak('final_km', 60)) {
      speak(getMessage('final_km', lang, st.vars), lang);
    }
  }, 5000);
}

export function stopEngine() {
  if (timer) clearInterval(timer);
  timer = null;
}
