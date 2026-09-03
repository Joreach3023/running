// RunPacer SwiftData-first history bootstrap
//
// Transitional strategy:
// - SwiftData is the authoritative ordered list of personal runs.
// - Each SwiftData run owns its complete detailed payload (GPS, splits, route image, pace, etc.).
// - The global SwiftData snapshot remains a temporary fallback for older records.
// - The existing web UI still reads userData.runs, so hydrate that array from RunPacerStorage.loadHistory().
// - localStorage remains a temporary fallback/mirror while the existing UI is migrated incrementally.

(function (global) {
  'use strict';

  const USER_DATA_KEY = 'runPacerUserData';
  let hydrationInFlight = null;

  function readLocalUserData() {
    try {
      return JSON.parse(global.localStorage.getItem(USER_DATA_KEY) || 'null');
    } catch (_) {
      return null;
    }
  }

  function updateLegacyUserData(runs) {
    let updatedRuntimeObject = false;

    // In the current classic-script app, `userData` is a global lexical binding
    // (`const userData = {...}`), so it is visible to later classic scripts even
    // though it is not a property of window.
    try {
      if (typeof userData !== 'undefined' && userData && typeof userData === 'object') {
        userData.runs = runs;
        global.localStorage.setItem(USER_DATA_KEY, JSON.stringify(userData));
        updatedRuntimeObject = true;
      }
    } catch (error) {
      console.warn('[SwiftData] Impossible de mettre à jour userData en mémoire:', error);
    }

    if (!updatedRuntimeObject) {
      const fallback = readLocalUserData() || {};
      fallback.runs = runs;
      global.localStorage.setItem(USER_DATA_KEY, JSON.stringify(fallback));
    }

    return updatedRuntimeObject;
  }

  function refreshExistingUI() {
    try {
      if (typeof updateHistory === 'function') updateHistory();
    } catch (error) {
      console.warn('[SwiftData] Rafraîchissement historique ignoré:', error);
    }

    try {
      if (typeof updateStats === 'function') updateStats();
    } catch (error) {
      console.warn('[SwiftData] Rafraîchissement statistiques ignoré:', error);
    }
  }

  async function hydrateNow() {
    if (hydrationInFlight) return hydrationInFlight;

    hydrationInFlight = (async function () {
      if (!global.RunPacerStorage || typeof global.RunPacerStorage.loadHistory !== 'function') {
        return { hydrated: false, reason: 'history-loader-unavailable' };
      }

      const result = await global.RunPacerStorage.loadHistory();
      if (!result || !Array.isArray(result.runs)) {
        return { hydrated: false, reason: 'invalid-history-result' };
      }

      // Never erase a non-empty legacy history because SwiftData unexpectedly
      // returned zero rows. The old data stays available as a safety net.
      if (result.source === 'swiftdata' && result.runs.length === 0) {
        return { hydrated: false, reason: 'empty-swiftdata-history', source: result.source };
      }

      updateLegacyUserData(result.runs);
      refreshExistingUI();

      const summary = {
        hydrated: true,
        source: result.source,
        runs: result.runs.length,
        perRunPayloadMatches: result.perRunPayloadMatches || 0,
        snapshotFallbackMatches: result.snapshotFallbackMatches || 0,
        detailedMatches: result.detailedMatches || 0,
        detailedCount: result.detailedCount || 0
      };
      console.log('[SwiftData] Historique UI hydraté:', summary);
      return summary;
    })().catch(function (error) {
      console.warn('[SwiftData] Hydratation historique ignorée; fallback local conservé:',
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
    // The storage bridge performs its initial local -> SwiftData mirror after
    // roughly 750 ms. Hydrate shortly afterwards so the snapshot and rows are ready.
    global.setTimeout(hydrateNow, 1400);
  }

  global.RunPacerHistoryBootstrap = {
    hydrateNow
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})(window);
