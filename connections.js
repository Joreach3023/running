(function() {
  const KEY = 'runPacerConnections';

  function load() {
    try {
      return JSON.parse(localStorage.getItem(KEY)) || {};
    } catch (e) {
      return {};
    }
  }

  function save(data) {
    localStorage.setItem(KEY, JSON.stringify(data));
  }

  function shouldShowOnboarding() {
    return !load().onboardingSeen;
  }

  function setOnboardingShown() {
    const data = load();
    data.onboardingSeen = true;
    save(data);
  }

  function isStravaConnected() {
    return !!load().stravaConnected;
  }

  function connectStrava() {
    const data = load();
    data.stravaConnected = true;
    save(data);
  }

  function disconnectStrava() {
    const data = load();
    data.stravaConnected = false;
    save(data);
  }

  function isGarminEnabled() {
    return false;
  }

  window.connections = {
    shouldShowOnboarding,
    setOnboardingShown,
    isStravaConnected,
    connectStrava,
    disconnectStrava,
    isGarminEnabled,
  };
})();
