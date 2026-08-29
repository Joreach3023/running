// RunPacer personal profile/progression bridge using the existing SwiftData snapshot.
// SwiftData owns the personal profile/progression state. localStorage remains a
// temporary compatibility surface for the legacy web UI and write-through path.
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
  const COMPATIBILITY_DEPTH_KEY = '__runPacerSwiftDataCompatibilityWriteDepth';

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

  function compatibilityWriteInProgress() {
    return Number(global[COMPATIBILITY_DEPTH_KEY] || 0) > 0;
  }

  function withCompatibilityWrite(callback) {
    global[COMPATIBILITY_DEPTH_KEY] = Number(global[COMPATIBILITY_DEPTH_KEY] || 0) + 1;
    try {
      return callback();
    } finally {
      global[COMPATIBILITY_DEPTH_KEY] = Math.max(
        0,
        Number(global[COMPATIBILITY_DEPTH_KEY] || 1) - 1
      );
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

  function buildSnapshotUserData(existingUserData, profile, progression) {
    // Preserve the old full snapshot as a frozen migration fallback. Only the
    // isolated personal-state section is updated from now on.
    const snapshotUserData = cloneJSON(existingUserData || {}, {});
    snapshotUserData[PERSONAL_STATE_KEY] = {
      version: PERSONAL_STATE_VERSION,
      profile: cloneJSON(profile || {}, {}),
      progression: cloneJSON(progression || {}, {})
    };
    return snapshotUserData;
  }

  async function savePersonalState(profile, progression, legacyUserData) {
    const bridge = requireStorageBridge();
    let existing = null;

    try {
      existing = await bridge.loadSnapshot();
    } catch (_) {
      // A missing old snapshot is fine; the dedicated state can create it.
    }

    const snapshotUserData = buildSnapshotUserData(
      existing && existing.userData,
      profile,
      progression
    );

    await bridge.saveSnapshot({
      userData: snapshotUserData,
      trainingPlan: existing ? existing.trainingPlan : undefined,
      deviceId: detectDeviceId(legacyUserData, existing)
    });

    return {
      saved: true,
      source: 'swiftdata',
      profileKeys: Object.keys(profile || {}).length,
      hasXP: progression && progression.xpRaw != null,
      hasBadges: progression && progression.badgesRaw != null,
      hasUserKey: progression && progression.userKey != null,
      bossRunBadgesExcluded: true
    };
  }

  async function syncPersonalStateFromLocalStorage() {
    const legacy = readLegacyPersonalState();

    if (!hasLegacyPersonalData(legacy)) {
      return { saved: false, reason: 'no-local-personal-state' };
    }

    const result = await savePersonalState(
      legacy.profile,
      legacy.progression,
      legacy.userData
    );

    const syncResult = Object.assign({}, result, { source: 'localstorage-write-through' });
    console.log('[SwiftData] Profil/progression synchronisés:', syncResult);
    return syncResult;
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
    if (value == null) return false;
    const text = String(value);
    if (global.localStorage.getItem(key) === text) return false;
    global.localStorage.setItem(key, text);
    return true;
  }

  function setUserDataCompatibilityProfile(profile) {
    const localUserData = readUserData() || {};
    const mergedLocalUserData = Object.assign({}, localUserData, profile || {});
    const nextJSON = JSON.stringify(mergedLocalUserData);
    if (global.localStorage.getItem(USER_DATA_KEY) === nextJSON) return false;
    global.localStorage.setItem(USER_DATA_KEY, nextJSON);
    return true;
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

    const progression = state.progression || {};
    let compatibilityWrites = 0;

    withCompatibilityWrite(function () {
      if (setUserDataCompatibilityProfile(profile)) compatibilityWrites += 1;
      if (setLocalStorageIfChanged(XP_KEY, progression.xpRaw)) compatibilityWrites += 1;
      if (setLocalStorageIfChanged(BADGES_KEY, progression.badgesRaw)) compatibilityWrites += 1;
      if (setLocalStorageIfChanged(USER_KEY, progression.userKey)) compatibilityWrites += 1;
    });

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
      compatibilityWrites,
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
      if (
        this === global.localStorage &&
        WATCHED_KEYS.has(key) &&
        !compatibilityWriteInProgress()
      ) {
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
  bridge.savePersonalState = savePersonalState;
  bridge.loadPersonalState = loadPersonalState;
  bridge.syncPersonalStateFromLocalStorage = syncPersonalStateFromLocalStorage;
  bridge.initialPersonalStateImportIfNeeded = initialPersonalStateImportIfNeeded;

  global.RunPacerPersonalState = {
    save: savePersonalState,
    load: loadPersonalState,
    syncNow: syncPersonalStateFromLocalStorage,
    initialImportIfNeeded: initialPersonalStateImportIfNeeded,
    hydrateNow
  };

  start();
})(window);
