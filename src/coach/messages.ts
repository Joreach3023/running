// Dictionary of coach messages with simple variable interpolation.
// Supports French and English languages.

export const messages: Record<'fr' | 'en', Record<string, string>> = {
  fr: {
    start_brief: "Objectif: {distance_target} à {pace_target}/km. On démarre tranquille 500 m.",
    warmup: "On chauffe: vise {pace_warmup}/km, respire 3-3.",
    pace_fast: "Un poil rapide. Relâche d’environ 2 %.",
    pace_slow: "Contrôlé. Stabilise ton effort, c’est parfait.",
    split: "{km} km, moyenne {pace_avg}/km. Tu es {delta_vs_target} vs l’objectif.",
    fatigue: "On allège 60 s, puis on repart propre. Regarde 10 m devant.",
    hill_up: "Montée: raccourcis un peu la foulée, garde l’effort.",
    hill_down: "Descente: laisse aller sans talonner.",
    hydration: "Prends quelques gorgées maintenant.",
    final_km: "Dernier km. Si tu as du jus: +5 s/km, épaules basses.",
    debrief: "Bravo! {distance} km en {time_total}, moy {pace_avg}/km."
  },
  en: {
    start_brief: "Goal: {distance_target} at {pace_target}/km. Easy first 500 m.",
    warmup: "Warming up: aim {pace_warmup}/km, breathe 3-3.",
    pace_fast: "A bit quick. Ease off about 2%.",
    pace_slow: "Controlled. Hold steady, that's great.",
    split: "{km} km, average {pace_avg}/km. You are {delta_vs_target} vs target.",
    fatigue: "Back off for 60 s, then build cleanly. Look 10 m ahead.",
    hill_up: "Hill: shorten your stride, keep the effort.",
    hill_down: "Downhill: let it roll without heel striking.",
    hydration: "Take a few sips now.",
    final_km: "Final km. If you can: +5 s/km, keep shoulders low.",
    debrief: "Well done! {distance} km in {time_total}, avg {pace_avg}/km."
  }
};

/**
 * Returns a formatted message for the given key and language.
 * Variables in the message are replaced using values provided in `vars`.
 */
export function getMessage(key: string, lang: 'fr' | 'en', vars: Record<string, any> = {}): string {
  const dict = messages[lang] || messages.fr;
  const template = dict[key] || '';
  return template.replace(/\{(.*?)\}/g, (_, v) => {
    const value = vars[v.trim()];
    return value !== undefined ? String(value) : '';
  });
}
