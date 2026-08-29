// RunPacer personal profile/progression bridge using the existing SwiftData snapshot.
// Keeps the current web/localStorage behavior intact while making SwiftData the
// authoritative backup for personal profile, XP and personal badges.
// Boss Run earned badges (`br_earned_badges`) remain outside this migration.

(function (global) {
  'use strict';

  const USER_DATA_KEY = 'runPacerUserData';
  const TRAINING_PLAN_KEY = 'runPacerTrainingPlan';
  const XP_KEY = 'runpacer_xp';
  const BADGES_KEY = 'runpacer_badges';
  const USER_KEY = 'runpacer_user_key';
  const PERSONAL_STATE_KEY = '__runPacerPersonalState';
  const PERSONAL_STATE_VERSION = 1;

  const WATCHED_KEYS = new Set([USER_DATA_KEY, XP_KEY, BADGES_KEY, USER_KEY]);
  let syncTimer = null;
  let syncInFlight = Promise.resolve();
  let storageHookInstalled = false;

  function storageBridge() {
    return global.RunPacerStorage;
  }

  function requireStorageBridge() {
    const bridge = storageBridge();
    if (!bridge || typeof bridge.saveSnapshot !== 'function' || typeof bridge.loadSnapshot !== 'function') {
      throw new Error('RunPacerStorage snapshot bridge is unavailable');
    }
    return bridge;
  }

  function parseJSON(value, fallback) {
    if (!value) return fallback;
    try {
      return JSON.parse(value);
    } catch (_) {
      return fallback;
    }
  }

  function cloneJSON(value, fallback) {
    try {
      return JSON.parse(JSON.stringify(value));
    } catch (_) {
      return fallback;
    }
  }

  function readUserData() {
    return parseJSON(global.localStorage.getItem(USER_DATA_KEY), null);
  }

  function readTrainingPlan(userData) {
    const direct = parseJSON(global.localStorage.getItem(TRAINING_PLAN_KEY), null);
    if (direct != null) return direct;
    if (userData && userData.trainingPlan != null) return userData.trainingPlan;
    return undefined;
  }

  function profileFromUserData(userData) {
    const profile = cloneJSON(userData || {}, {});

    // These already have dedicated native storage and must not define the
    // personal-profile source of truth.
    delete profile.runs;
    delete profile.trainingPlan;
    delete profile[PERSONAL_STATE_KEY];

    // Never migrate OAuth secrets into the personal CloudKit-bound profile.
    delete profile.stravaToken;
    delete profile.stravaRefreshToken;
    delete profile.stravaExpiresAt;

    return profile;
  }

  function readLegacyPersonalState() {
    const userData = readUserData();
    const xpRaw = global.localStorage.getItem(XP_KEY);
    const badgesRaw = global.localStorage.getItem(BADGES_KEY);
    const userKey = global.localStorage.getItem(USER_KEY);

    return {
      userData,
      trainingPlan: readTrainingPlan(userData),
      profile: profileFromUserData(userData),
      progression: {
        xpRaw,
        badgesRaw,
        userKey
      }
    };
  }

  function detectDeviceId(userData, snapshot) {
    if (snapshot && snapshot.deviceId) return snapshot.deviceId;
    if (userData && userData.deviceId) return String(userData.deviceId);

    const candidates = ['device_id', 'deviceId', 'runPacerDeviceId', 'runpacer_device_id'];
    for (const key of candidates) {
      const value = global.localStorage.getItem(key);
      if (value) return value;
    }
    return undefined;
  }

  function hasLegacyPersonalData(state) {
    if (!state) return false;
    if (state.userData && Object.keys(state.userData).length > 0) return true;
    return state.progression.xpRaw != null ||
      state.progression.badgesRaw != null ||
      state.progression.userKey != null;
  }

  function buildSnapshotUserData(existingUserData, legacyState) {
    // Preserve the complete snapshot as a safety net for the migration while
    // adding an isolated, versioned personal-state section.
    const snapshotUserData = Object.assign(
      {},
      cloneJSON(existingUserData || {}, {}),
      cloneJSON(legacyState.userData || {}, {})
    );

    snapshotUserData[PERSONAL_STATE_KEY] = {
      version: PERSONAL_STATE_VERSION,
      profile: legacyState.profile,
      progression: legacyState.progression
    };

    return snapshotUserData;
  }

  async function syncPersonalStateFromLocalStorage() {
    const bridge = requireStorageBridge();
    const legacy = readLegacyPersonalState();

    if (!hasLegacyPersonalData(legacy)) {
      return { saved: false, reason: 'no-local-personal-state' };
    }

    let existing = null;
    try {
      existing = await bridge.loadSnapshot();
    } catch (_) {
      // A missing/old snapshot must not block migration from the current local data.
    }

    const snapshotUserData = buildSnapshotUserData(existing && existing.userData, legacy);
    const trainingPlan = legacy.trainingPlan !== undefined
      ? legacy.trainingPlan
      : (existing ? existing.trainingPlan : undefined);

    await bridge.saveSnapshot({
      userData: snapshotUserData,
      trainingPlan,
      deviceId: detectDeviceId(legacy.userData, existing)
    });

    const result = {
      saved: true,
      source: 'localstorage',
      profileKeys: Object.keys(legacy.profile).length,
      hasXP: legacy.progression.xpRaw != null,
      hasBadges: legacy.progression.badgesRaw != null,
      hasUserKey: legacy.progression.userKey != null,
      bossRunBadgesExcluded: true
    };
    console.log('[SwiftData] Profil/progression synchronisés:', result);
    return result;
  }

  async function loadPersonalState() {
    const bridge = requireStorageBridge();
    const snapshot = await bridge.loadSnapshot();
    const nativeState = snapshot && snapshot.userData
      ? snapshot.userData[PERSONAL_STATE_KEY]
      : null;

    if (!nativeState || typeof nativeState !== 'object') {
      return {
        exists: false,
        source: 'none',
        version: 0,
        profile: null,
        progression: null,
        updatedAt: snapshot ? snapshot.updatedAt : null
      };
    }

    return {
      exists: true,
      source: 'swiftdata',
      version: nativeState.version || 1,
      profile: nativeState.profile || {},
      progression: nativeState.progression || {},
      updatedAt: snapshot ? snapshot.updatedAt : null
    };
  }

  async function initialPersonalStateImportIfNeeded() {
    const native = await loadPersonalState();
    if (native.exists) {
      const result = {
        imported: false,
        reason: 'swiftdata-personal-state-already-populated',
        profileKeys: Object.keys(native.profile || {}).length,
        hasXP: native.progression && native.progression.xpRaw != null,
        hasBadges: native.progression && native.progression.badgesRaw != null
      };
      console.log('[SwiftData] Démarrage profil SwiftData-first:', result);
      return result;
    }

    const synced = await syncPersonalStateFromLocalStorage();
    return Object.assign({
      imported: !!synced.saved,
      reason: synced.saved ? 'swiftdata-personal-state-empty' : synced.reason
    }, synced);
  }

  function setLocalStorageIfChanged(key, value) {
    if (value == null) return;
    if (global.localStorage.getItem(key) !== String(value)) {
      global.localStorage.setItem(key, String(value));
    }
  }

  async function hydrateNow() {
    let state = await loadPersonalState();

    if (!state.exists) {
      const imported = await initialPersonalStateImportIfNeeded();
      if (!imported.imported) {
        return { hydrated: false, reason: imported.reason };
      }
      state = await loadPersonalState();
    }

    const profile = state.profile || {};
    let runtimeUpdated = false;

    try {
      if (typeof userData !== 'undefined' && userData && typeof userData === 'object') {
        Object.assign(userData, profile);
        runtimeUpdated = true;
      }
    } catch (error) {
      console.warn('[SwiftData] Profil runtime non mis à jour:', error);
    }

    // Keep the legacy key hydrated for the existing app without touching the
    // already-migrated runs/training plan arrays.
    const localUserData = readUserData() || {};
    const mergedLocalUserData = Object.assign({}, localUserData, profile);
    global.localStorage.setItem(USER_DATA_KEY, JSON.stringify(mergedLocalUserData));

    const progression = state.progression || {};
    setLocalStorageIfChanged(XP_KEY, progression.xpRaw);
    setLocalStorageIfChanged(BADGES_KEY, progression.badgesRaw);
    setLocalStorageIfChanged(USER_KEY, progression.userKey);

    try {
      if (profile.currentPace != null) {
        const element = document.getElementById('current-pace-input');
        if (element) element.value = profile.currentPace;
      }
      if (profile.targetPace != null) {
        const element = document.getElementById('target-pace-input');
        if (element) element.value = profile.targetPace;
      }
      if (profile.eventDate != null) {
        const element = document.getElementById('event-date-input');
        if (element) element.value = profile.eventDate;
      }
      if (profile.theme && typeof applyTheme === 'function') {
        applyTheme(profile.theme);
      }
      if (typeof updateStats === 'function') {
        updateStats();
      }
    } catch (error) {
      console.warn('[SwiftData] Rafraîchissement profil ignoré:', error);
    }

    const result = {
      hydrated: true,
      source: 'swiftdata',
      profileKeys: Object.keys(profile).length,
      hasXP: progression.xpRaw != null,
      hasBadges: progression.badgesRaw != null,
      runtimeUpdated,
      bossRunBadgesExcluded: true
    };
    console.log('[SwiftData] Profil/progression UI hydratés:', result);
    return result;
  }

  function queueSync() {
    if (syncTimer) global.clearTimeout(syncTimer);
    syncTimer = global.setTimeout(function () {
      syncTimer = null;
      syncInFlight = syncInFlight
        .then(syncPersonalStateFromLocalStorage)
        .catch(function (error) {
          console.warn('[SwiftData] Synchronisation profil différée:',
            error && error.message ? error.message : error);
        });
    }, 220);
  }

  function installStorageHook() {
    if (storageHookInstalled || !global.Storage || !global.localStorage) return;
    storageHookInstalled = true;

    const previousSetItem = global.Storage.prototype.setItem;
    global.Storage.prototype.setItem = function (key, value) {
      const result = previousSetItem.apply(this, arguments);
      if (this === global.localStorage && WATCHED_KEYS.has(key)) {
        queueSync();
      }
      return result;
    };
  }

  function start() {
    installStorageHook();

    global.setTimeout(function () {
      syncInFlight = syncInFlight
        .then(initialPersonalStateImportIfNeeded)
        .catch(function (error) {
          console.warn('[SwiftData] Import initial profil ignoré:',
            error && error.message ? error.message : error);
        });
    }, 1150);

    global.setTimeout(function () {
      hydrateNow().catch(function (error) {
        console.warn('[SwiftData] Hydratation profil ignorée:',
          error && error.message ? error.message : error);
      });
    }, 1900);
  }

  const bridge = global.RunPacerStorage || (global.RunPacerStorage = {});
  bridge.loadPersonalState = loadPersonalState;
  bridge.syncPersonalStateFromLocalStorage = syncPersonalStateFromLocalStorage;
  bridge.initialPersonalStateImportIfNeeded = initialPersonalStateImportIfNeeded;

  global.RunPacerPersonalState = {
    load: loadPersonalState,
    syncNow: syncPersonalStateFromLocalStorage,
    initialImportIfNeeded: initialPersonalStateImportIfNeeded,
    hydrateNow
  };

  start();
})(window);
