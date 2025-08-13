const { expect } = require('chai');
const fs = require('fs');
const path = require('path');

const statePath = path.join(__dirname, '..', 'connection-state.json');

function loadFreshModule() {
  delete require.cache[require.resolve('../src/state/connections')];
  return require('../src/state/connections');
}

describe('connection state', () => {
  beforeEach(() => {
    if (fs.existsSync(statePath)) {
      fs.unlinkSync(statePath);
    }
  });

  it('shows onboarding only once', () => {
    let state = loadFreshModule();
    expect(state.shouldShowOnboarding()).to.be.true;
    state.setOnboardingShown();
    expect(state.shouldShowOnboarding()).to.be.false;

    state = loadFreshModule();
    expect(state.shouldShowOnboarding()).to.be.false;
  });

  it('persists strava connection', () => {
    let state = loadFreshModule();
    expect(state.isStravaConnected()).to.be.false;
    state.connectStrava();
    expect(state.isStravaConnected()).to.be.true;

    state = loadFreshModule();
    expect(state.isStravaConnected()).to.be.true;

    state.disconnectStrava();
    expect(state.isStravaConnected()).to.be.false;
  });

  it('garmin is disabled', () => {
    const state = loadFreshModule();
    expect(state.isGarminEnabled()).to.be.false;
  });
});
