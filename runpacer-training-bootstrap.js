// RunPacer SwiftData-first training-plan bootstrap.
// Hydrates the legacy `userData.trainingPlan` + localStorage key so the current
// web UI keeps working unchanged while SwiftData remains authoritative.

(function (global) {
  'use strict';

  const PLAN_KEY = 'runPacerTrainingPlan';
  const COMPATIBILITY_DEPTH_KEY = '__runPacerSwiftDataCompatibilityWriteDepth';
  let hydrationInFlight = null;

  function parseJSON(value, fallback) {
    if (!value) return fallback;
    try {
      return JSON.parse(value);
    } catch (_) {
      return fallback;
    }
  }

  function readLocalPlan() {
    return parseJSON(global.localStorage.getItem(PLAN_KEY), null);
  }

  function itemCount(plan) {
    return Array.isArray(plan) ? plan.length : (plan == null ? 0 : 1);
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

  function applyPlanToLegacyApp(plan) {
    let runtimeUpdated = false;

    try {
      if (typeof userData !== 'undefined' && userData && typeof userData === 'object') {
        userData.trainingPlan = plan;
        runtimeUpdated = true;
      }
    } catch (error) {
      console.warn('[SwiftData] Impossible de mettre à jour userData.trainingPlan:', error);
    }

    const nextJSON = JSON.stringify(plan);
    let compatibilityWrite = false;
    if (global.localStorage.getItem(PLAN_KEY) !== nextJSON) {
      withCompatibilityWrite(function () {
        global.localStorage.setItem(PLAN_KEY, nextJSON);
      });
      compatibilityWrite = true;
    }

    try {
      if (typeof updateTrainingPlanDisplay === 'function') {
        updateTrainingPlanDisplay();
      }
    } catch (error) {
      console.warn('[SwiftData] Rafraîchissement visuel du plan ignoré:', error);
    }

    return { runtimeUpdated, compatibilityWrite };
  }

  async function hydrateNow() {
    if (hydrationInFlight) return hydrationInFlight;

    hydrationInFlight = (async function () {
      if (!global.RunPacerStorage || typeof global.RunPacerStorage.loadTrainingPlan !== 'function') {
        return { hydrated: false, reason: 'training-plan-loader-unavailable' };
      }

      const native = await global.RunPacerStorage.loadTrainingPlan();
      const localPlan = readLocalPlan();

      let plan;
      let source;

      if (native && native.exists) {
        plan = native.plan;
        source = 'swiftdata';

        // Safety against a startup race where the app generates a real plan
        // after an empty native placeholder was created.
        if (itemCount(plan) === 0 && itemCount(localPlan) > 0) {
          plan = localPlan;
          source = 'localstorage-safety';
          await global.RunPacerStorage.saveTrainingPlan(plan);
        }
      } else if (localPlan != null) {
        plan = localPlan;
        source = 'localstorage-fallback';
        await global.RunPacerStorage.saveTrainingPlan(plan);
      } else {
        return { hydrated: false, reason: 'no-training-plan' };
      }

      const applied = applyPlanToLegacyApp(plan);
      const summary = {
        hydrated: true,
        source,
        items: itemCount(plan),
        runtimeUpdated: applied.runtimeUpdated,
        compatibilityWrite: applied.compatibilityWrite
      };
      console.log('[SwiftData] Plan UI hydraté:', summary);
      return summary;
    })().catch(function (error) {
      console.warn('[SwiftData] Hydratation du plan ignorée; plan local conservé:',
        error && error.message ? error.message : error);
      return {
        hydrated: false,
        reason: 'load-failed',
        error: error && error.message ? error.message : String(error)
      };
    }).finally(function () {
      hydrationInFlight = null;
    });

    return hydrationInFlight;
  }

  function start() {
    global.setTimeout(hydrateNow, 1650);
  }

  global.RunPacerTrainingBootstrap = { hydrateNow };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})(window);
