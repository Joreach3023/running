// RunPacer training-plan bridge: legacy localStorage <-> native SwiftData.
// SwiftData is authoritative for reads; localStorage remains a temporary
// write-through/compatibility surface for the existing web UI.

(function (global) {
  'use strict';

  const PLAN_KEY = 'runPacerTrainingPlan';
  const USER_DATA_KEY = 'runPacerUserData';
  const COMPATIBILITY_DEPTH_KEY = '__runPacerSwiftDataCompatibilityWriteDepth';

  let planTimer = null;
  let planSyncInFlight = Promise.resolve();
  let storageHookInstalled = false;

  function nativePlugin() {
    return global.Capacitor &&
      global.Capacitor.Plugins &&
      global.Capacitor.Plugins.RunPacerStorage;
  }

  async function requirePlugin() {
    const plugin = nativePlugin();
    if (!plugin) throw new Error('RunPacerStorage native plugin is unavailable');
    return plugin;
  }

  function parseJSON(value, fallback) {
    if (!value) return fallback;
    try {
      return JSON.parse(value);
    } catch (_) {
      return fallback;
    }
  }

  function compatibilityWriteInProgress() {
    return Number(global[COMPATIBILITY_DEPTH_KEY] || 0) > 0;
  }

  function readLegacyPlan() {
    const direct = parseJSON(global.localStorage.getItem(PLAN_KEY), null);
    if (direct != null) return direct;

    const userData = parseJSON(global.localStorage.getItem(USER_DATA_KEY), null);
    if (userData && userData.trainingPlan != null) return userData.trainingPlan;

    return null;
  }

  function itemCount(plan) {
    return Array.isArray(plan) ? plan.length : (plan == null ? 0 : 1);
  }

  async function saveTrainingPlan(plan) {
    const plugin = await requirePlugin();
    return plugin.saveTrainingPlan({
      payloadJson: JSON.stringify(plan == null ? [] : plan)
    });
  }

  async function loadTrainingPlan() {
    const plugin = await requirePlugin();
    const result = await plugin.loadTrainingPlan();
    if (!result || !result.exists) {
      return { exists: false, plan: null, updatedAt: null };
    }

    return {
      exists: true,
      plan: parseJSON(result.payloadJson, []),
      updatedAt: result.updatedAt || null
    };
  }

  async function syncTrainingPlanFromLocalStorage() {
    const plan = readLegacyPlan();
    if (plan == null) {
      return { saved: false, reason: 'no-local-training-plan', items: 0 };
    }

    await saveTrainingPlan(plan);
    const result = { saved: true, reason: 'local-plan-synced', items: itemCount(plan) };
    console.log('[SwiftData] Plan d’entraînement synchronisé:', result);
    return result;
  }

  async function initialTrainingPlanImportIfNeeded() {
    const localPlan = readLegacyPlan();
    const native = await loadTrainingPlan();

    if (native.exists) {
      // Safety: never let an old empty native placeholder win over a real
      // legacy plan that appeared during startup.
      if (itemCount(native.plan) === 0 && itemCount(localPlan) > 0) {
        await saveTrainingPlan(localPlan);
        const result = {
          imported: true,
          reason: 'native-plan-empty-local-plan-present',
          items: itemCount(localPlan)
        };
        console.log('[SwiftData] Plan local récupéré au démarrage:', result);
        return result;
      }

      const result = {
        imported: false,
        reason: 'swiftdata-plan-already-populated',
        items: itemCount(native.plan)
      };
      console.log('[SwiftData] Démarrage plan SwiftData-first:', result);
      return result;
    }

    if (localPlan == null) {
      const result = { imported: false, reason: 'no-local-training-plan', items: 0 };
      console.log('[SwiftData] Aucun plan local à importer:', result);
      return result;
    }

    await saveTrainingPlan(localPlan);
    const result = {
      imported: true,
      reason: 'swiftdata-plan-empty',
      items: itemCount(localPlan)
    };
    console.log('[SwiftData] Plan local importé:', result);
    return result;
  }

  function queuePlanSync() {
    if (planTimer) global.clearTimeout(planTimer);
    planTimer = global.setTimeout(function () {
      planTimer = null;
      planSyncInFlight = planSyncInFlight
        .then(syncTrainingPlanFromLocalStorage)
        .catch(function (error) {
          console.warn('[SwiftData] Synchronisation du plan différée:',
            error && error.message ? error.message : error);
        });
    }, 120);
  }

  function installStorageHook() {
    if (storageHookInstalled || !global.Storage || !global.localStorage) return;
    storageHookInstalled = true;

    // runpacer-storage.js already wraps setItem for user data. Wrapping the
    // current implementation here preserves that behavior and adds plan writes.
    const previousSetItem = global.Storage.prototype.setItem;
    global.Storage.prototype.setItem = function (key, value) {
      const result = previousSetItem.apply(this, arguments);
      if (
        this === global.localStorage &&
        (key === PLAN_KEY || key === USER_DATA_KEY) &&
        !compatibilityWriteInProgress()
      ) {
        queuePlanSync();
      }
      return result;
    };
  }

  function startAutomaticPlanSync() {
    installStorageHook();
    global.setTimeout(function () {
      planSyncInFlight = planSyncInFlight
        .then(initialTrainingPlanImportIfNeeded)
        .catch(function (error) {
          console.warn('[SwiftData] Import initial du plan ignoré:',
            error && error.message ? error.message : error);
        });
    }, 900);
  }

  const storage = global.RunPacerStorage || (global.RunPacerStorage = {});
  storage.saveTrainingPlan = saveTrainingPlan;
  storage.loadTrainingPlan = loadTrainingPlan;
  storage.syncTrainingPlanFromLocalStorage = syncTrainingPlanFromLocalStorage;
  storage.initialTrainingPlanImportIfNeeded = initialTrainingPlanImportIfNeeded;

  startAutomaticPlanSync();
})(window);
