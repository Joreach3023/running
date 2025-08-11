// Placeholder for speech-to-text command recognition.
// Actual implementation can use native APIs or Web Speech later.

type CommandCallback = (command: string) => void;
let callback: CommandCallback | null = null;

export async function init() {
  // future initialization for native speech recognition
}

export function onCommand(cb: CommandCallback) {
  callback = cb;
}

export function dispose() {
  callback = null;
}

// Utility to trigger a command manually (useful for tests or mocks)
export function _emit(command: string) {
  callback?.(command);
}
