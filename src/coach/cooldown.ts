// Simple cooldown manager to prevent repeated voice prompts
// Maintains last time a key spoke and enforces a minimum interval

const lastSpoken: Record<string, number> = {};

/**
 * Returns true if the key is allowed to speak based on the cooldown.
 * When true, the timestamp is updated. When false, the cooldown is still active.
 * @param key Identifier of the message category
 * @param seconds Cooldown duration in seconds
 */
export function shouldSpeak(key: string, seconds: number): boolean {
  const now = Date.now();
  const last = lastSpoken[key] ?? 0;
  if (now - last >= seconds * 1000) {
    lastSpoken[key] = now;
    return true;
  }
  return false;
}

/**
 * Resets cooldowns. Passing a key resets only that entry; otherwise all are cleared.
 */
export function resetCooldown(key?: string) {
  if (key) {
    delete lastSpoken[key];
  } else {
    Object.keys(lastSpoken).forEach(k => delete lastSpoken[k]);
  }
}

export const _debug = { lastSpoken };
