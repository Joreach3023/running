import { startEngine, stopEngine } from './coachEngine';
import { stop as stopTTS } from './tts';

/**
 * Starts the voice coach.
 */
export function startCoach(lang: 'fr' | 'en' = 'fr') {
  startEngine(lang);
}

/**
 * Stops the coach, TTS and attempts to shut down background GPS tracking.
 */
export function stopCoach() {
  stopEngine();
  stopTTS();

  // Attempt to stop Capacitor background geolocation if available
  const bg: any = (globalThis as any).BackgroundGeolocation;
  bg?.stop?.();
  bg?.removeAllListeners?.();

  // Clear standard geolocation watches if a watchId is stored globally
  const watchId: any = (globalThis as any).__geoWatchId;
  if (typeof watchId === 'number' && globalThis.navigator?.geolocation) {
    globalThis.navigator.geolocation.clearWatch(watchId);
  }
}
