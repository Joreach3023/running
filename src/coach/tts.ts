// Minimal text-to-speech wrapper with queue handling.
// Uses the Web Speech API when available; otherwise falls back to console logs.

let speaking = false;
const queue: { text: string; lang: 'fr' | 'en' }[] = [];

function nativeSpeak(text: string, lang: 'fr' | 'en'): Promise<void> {
  // Browser environment
  if (typeof window !== 'undefined' && (window as any).speechSynthesis) {
    return new Promise(resolve => {
      const utter = new SpeechSynthesisUtterance(text);
      utter.lang = lang === 'fr' ? 'fr-FR' : 'en-US';
      utter.onend = () => resolve();
      (window as any).speechSynthesis.speak(utter);
    });
  }
  // Node or unsupported environment: log and resolve immediately
  console.log(`[TTS:${lang}] ${text}`);
  return Promise.resolve();
}

function nativeStop() {
  if (typeof window !== 'undefined' && (window as any).speechSynthesis) {
    (window as any).speechSynthesis.cancel();
  }
}

/**
 * Enqueue text to be spoken. A basic deduplication prevents repeated messages.
 */
export async function speak(text: string, lang: 'fr' | 'en') {
  const last = queue[queue.length - 1];
  if (last && last.text === text) return; // dedupe consecutive
  queue.push({ text, lang });
  if (speaking) return;
  speaking = true;
  while (queue.length) {
    const item = queue.shift()!;
    await nativeSpeak(item.text, item.lang);
  }
  speaking = false;
}

/**
 * Stops current speech and clears the queue.
 */
export function stop() {
  queue.length = 0;
  nativeStop();
  speaking = false;
}

export const _debug = { queue };
