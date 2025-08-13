const fs = require('fs');
const path = require('path');

// Persistent storage for connection and onboarding state.
// Data is stored in a JSON file at the project root so it can
// survive across module reloads and application restarts.
const DATA_FILE = path.join(__dirname, '../../connection-state.json');

let cache = null;

function load() {
  if (!cache) {
    try {
      const txt = fs.readFileSync(DATA_FILE, 'utf8');
      cache = JSON.parse(txt);
    } catch (err) {
      cache = { onboardingSeen: false, stravaConnected: false };
    }
  }
  return cache;
}

function save() {
  fs.writeFileSync(DATA_FILE, JSON.stringify(cache));
}

// Onboarding state -----------------------------------------------------------
function shouldShowOnboarding() {
  return !load().onboardingSeen;
}

function setOnboardingShown() {
  load();
  cache.onboardingSeen = true;
  save();
}

// Strava connection ----------------------------------------------------------
function isStravaConnected() {
  return !!load().stravaConnected;
}

function connectStrava() {
  load();
  cache.stravaConnected = true;
  save();
}

function disconnectStrava() {
  load();
  cache.stravaConnected = false;
  save();
}

// Garmin is not yet available ------------------------------------------------
function isGarminEnabled() {
  return false;
}

// Utility for tests ----------------------------------------------------------
function resetForTests() {
  cache = null;
  if (fs.existsSync(DATA_FILE)) {
    fs.unlinkSync(DATA_FILE);
  }
}

module.exports = {
  shouldShowOnboarding,
  setOnboardingShown,
  isStravaConnected,
  connectStrava,
  disconnectStrava,
  isGarminEnabled,
  resetForTests,
  DATA_FILE,
};
