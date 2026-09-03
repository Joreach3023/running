// RunPacer native personal-storage bridge (Capacitor 7 / iOS 17+)
//
// SwiftData-first strategy:
// - Personal runs are written directly to dedicated SwiftData rows.
// - Each run keeps its complete payload on its SwiftData row.
// - Displayed personal history reads from SwiftData first; the old global
//   snapshot remains only as a frozen migration fallback for pre-payload rows.
// - Ordinary localStorage userData writes no longer mirror runs automatically.
// - A manual sync/import path remains available as a recovery tool for legacy
//   installations where SwiftData is empty or incomplete.
// - Boss Runs, friends, invites and other shared/social data stay in Supabase.

(function (global) {
  'use strict';

  const USER_DATA_KEY = 'runPacerUserData';
  const RUN_ID_MAP_KEY = 'runPacerSwiftDataRunIds';
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  let syncInFlight = Promise.resolve();

  function nativePlugin() {
    return global.Capacitor &&
      global.Capacitor.Plugins &&
      global.Capacitor.Plugins.RunPacerStorage;
  }

  async function requirePlugin() {
    const plugin = nativePlugin();
    if (!plugin) {
      throw new Error('RunPacerStorage native plugin is unavailable');
    }
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

  function payloadJSONForRun(run) {
    try {
      return JSON.stringify(run || {});
    } catch (error) {
      console.warn('[SwiftData] Payload de course non sérialisable; détails conservés via snapshot:',
        error && error.message ? error.message : error);
      return null;
    }
  }

  function numberOrZero(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
  }

  function durationForRun(run) {
    return Math.max(0, Math.round(numberOrZero(
      run.durationSecs ?? run.duration_secs ?? run.duration
    )));
  }

  function distanceForRun(run) {
    return Math.max(0, numberOrZero(
      run.distanceKm ?? run.distance_km ?? run.distance
    ));
  }

  function normalizeDateValue(value) {
    if (value == null || value === '') return null;

    if (typeof value === 'number' && Number.isFinite(value)) {
      const ms = value > 100000000000 ? value : value * 1000;
      const numericDate = new Date(ms);
      return Number.isNaN(numericDate.getTime()) ? null : numericDate.toISOString();
    }

    if (typeof value !== 'string') return null;
    let text = value.trim();
    if (!text) return null;

    if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
      return text + 'T12:00:00Z';
    }

    if (/^\d{4}-\d{2}-\d{2}\s/.test(text)) {
      text = text.replace(' ', 'T');
      text = text.replace(/\.(\d{3})\d+/, '.$1');
      text = text.replace(/\+00$/, 'Z');
    }

    const parsed = new Date(text);
    if (Number.isNaN(parsed.getTime())) return null;
    return parsed.toISOString();
  }

  function dateCandidatesForRun(run) {
    return [
      run && run.startTime,
      run && run.start_time,
      run && run.date,
      run && run.runDate,
      run && run.run_date,
      run && run.createdAt,
      run && run.created_at,
      run && run.timestamp
    ];
  }

  function normalizedDateForRun(run) {
    for (const candidate of dateCandidatesForRun(run || {})) {
      const normalized = normalizeDateValue(candidate);
      if (normalized) return normalized;
    }
    return null;
  }

  function dateForRun(run) {
    const normalized = normalizedDateForRun(run);
    if (normalized) return normalized;

    const fallback = new Date().toISOString();
    console.warn('[SwiftData] Date historique introuvable; utilisation de la date actuelle pour:', {
      name: nameForRun(run || {}),
      distanceKm: distanceForRun(run || {}),
      durationSecs: durationForRun(run || {})
    });
    return fallback;
  }

  function createdAtForRun(run, runDate) {
    const candidates = [
      run && run.createdAt,
      run && run.created_at,
      run && run.startTime,
      run && run.start_time,
      run && run.date
    ];
    for (const candidate of candidates) {
      const normalized = normalizeDateValue(candidate);
      if (normalized) return normalized;
    }
    return runDate;
  }

  function nameForRun(run) {
    return run.name || run.typeName || run.type_name || 'Course';
  }

  function fingerprintRun(run) {
    return JSON.stringify([
      run.startTime || run.start_time || run.createdAt || run.created_at || run.date || '',
      run.type || run.typeName || run.type_name || '',
      String(distanceForRun(run)),
      String(durationForRun(run)),
      run.pace || '',
      run.strava_activity_id || run.stravaActivityId || ''
    ]);
  }

  function loadRunIdMap() {
    return parseJSON(global.localStorage.getItem(RUN_ID_MAP_KEY), {});
  }

  function stableRunId(run) {
    const directId = run && (run.id || run.swiftDataId || run.swift_data_id);
    if (typeof directId === 'string' && UUID_RE.test(directId)) {
      return directId;
    }

    const fingerprint = fingerprintRun(run || {});
    const map = loadRunIdMap();
    if (map[fingerprint] && UUID_RE.test(map[fingerprint])) {
      return map[fingerprint];
    }

    const newId = global.crypto && typeof global.crypto.randomUUID === 'function'
      ? global.crypto.randomUUID()
      : fallbackUUID();
    map[fingerprint] = newId;
    global.localStorage.setItem(RUN_ID_MAP_KEY, JSON.stringify(map));
    return newId;
  }

  function fallbackUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  function paceFromRun(distanceKm, durationSecs) {
    if (!(distanceKm > 0) || !(durationSecs > 0)) return '--:--';
    const secondsPerKm = durationSecs / distanceKm;
    const minutes = Math.floor(secondsPerKm / 60);
    const seconds = Math.round(secondsPerKm % 60);
    const normalizedMinutes = seconds === 60 ? minutes + 1 : minutes;
    const normalizedSeconds = seconds === 60 ? 0 : seconds;
    return `${normalizedMinutes}:${String(normalizedSeconds).padStart(2, '0')}`;
  }

  function calendarDay(value) {
    const normalized = normalizeDateValue(value);
    return normalized ? normalized.slice(0, 10) : '';
  }

  function historyMatchKey(run) {
    return [
      calendarDay(normalizedDateForRun(run)),
      String((run && (run.type || run.typeName || run.type_name)) || ''),
      distanceForRun(run).toFixed(3),
      String(durationForRun(run))
    ].join('|');
  }

  function findDetailedRun(structuredRun, detailRuns, usedIndexes) {
    const structuredId = structuredRun && structuredRun.id;
    if (structuredId) {
      const byId = detailRuns.findIndex((run, index) =>
        !usedIndexes.has(index) &&
        (run.id === structuredId || run.swiftDataId === structuredId || run.swift_data_id === structuredId)
      );
      if (byId !== -1) return byId;
    }

    const structuredKey = historyMatchKey(structuredRun || {});
    const exact = detailRuns.findIndex((run, index) =>
      !usedIndexes.has(index) && historyMatchKey(run) === structuredKey
    );
    if (exact !== -1) return exact;

    const targetType = String(structuredRun.type || '');
    const targetDistance = distanceForRun(structuredRun);
    const targetDuration = durationForRun(structuredRun);
    return detailRuns.findIndex((run, index) =>
      !usedIndexes.has(index) &&
      String(run.type || run.typeName || run.type_name || '') === targetType &&
      Math.abs(distanceForRun(run) - targetDistance) < 0.001 &&
      durationForRun(run) === targetDuration
    );
  }

  function mergeHistoryRun(structuredRun, detailedRun) {
    const merged = detailedRun ? Object.assign({}, detailedRun) : {};
    const dateISO = normalizeDateValue(structuredRun.date) || new Date().toISOString();
    const distanceKm = distanceForRun(structuredRun);
    const durationSecs = durationForRun(structuredRun);

    merged.id = structuredRun.id;
    merged.swiftDataId = structuredRun.id;
    merged.name = structuredRun.name || merged.name || merged.typeName || 'Course';
    merged.typeName = merged.typeName || structuredRun.name || merged.name || 'Course';
    merged.type = structuredRun.type || merged.type || 'Run';
    merged.distanceKm = distanceKm;
    merged.distance = distanceKm.toFixed(2);
    merged.durationSecs = durationSecs;
    merged.duration = durationSecs;
    merged.date = dateISO.slice(0, 10);
    merged.startTime = merged.startTime || dateISO;
    merged.createdAt = structuredRun.createdAt || merged.createdAt || dateISO;
    merged.source = structuredRun.source || merged.source || 'runpacer';
    merged.notes = structuredRun.notes || merged.notes || '';
    merged.pace = merged.pace || paceFromRun(distanceKm, durationSecs);

    return merged;
  }

  async function status() {
    const plugin = await requirePlugin();
    return plugin.status();
  }

  async function saveRun(run) {
    const plugin = await requirePlugin();
    const id = stableRunId(run || {});
    const runDate = dateForRun(run || {});
    const payloadJson = payloadJSONForRun(run || {});
    return plugin.saveRun({
      id,
      name: nameForRun(run || {}),
      distanceKm: distanceForRun(run || {}),
      durationSecs: durationForRun(run || {}),
      date: runDate,
      type: (run && (run.type || run.typeName)) || 'Run',
      source: (run && run.source) || 'runpacer',
      notes: (run && run.notes) || undefined,
      createdAt: createdAtForRun(run || {}, runDate),
      payloadJson: payloadJson || undefined
    });
  }

  async function listRuns() {
    const plugin = await requirePlugin();
    const result = await plugin.listRuns();
    return result.runs || [];
  }

  async function loadRunPayload(id) {
    const plugin = await requirePlugin();
    const result = await plugin.loadRunPayload({ id });
    if (!result || !result.exists || !result.payloadJson) return null;
    return parseJSON(result.payloadJson, null);
  }

  async function deleteRun(idOrOptions) {
    const plugin = await requirePlugin();
    const id = typeof idOrOptions === 'string'
      ? idOrOptions
      : idOrOptions && idOrOptions.id;
    return plugin.deleteRun({ id });
  }

  async function saveSnapshot({ userData, trainingPlan, deviceId } = {}) {
    const plugin = await requirePlugin();
    return plugin.saveSnapshot({
      userDataJson: userData == null ? undefined : JSON.stringify(userData),
      trainingPlanJson: trainingPlan == null ? undefined : JSON.stringify(trainingPlan),
      deviceId: deviceId || undefined
    });
  }

  async function loadSnapshot() {
    const plugin = await requirePlugin();
    const result = await plugin.loadSnapshot();
    if (!result.exists) return null;

    return {
      userData: result.userDataJson ? JSON.parse(result.userDataJson) : null,
      trainingPlan: result.trainingPlanJson ? JSON.parse(result.trainingPlanJson) : null,
      deviceId: result.deviceId || null,
      updatedAt: result.updatedAt || null
    };
  }

  async function loadHistory() {
    const structuredRuns = await listRuns();
    let snapshot = null;

    try {
      snapshot = await loadSnapshot();
    } catch (error) {
      console.warn('[SwiftData] Snapshot détaillé indisponible:', error && error.message ? error.message : error);
    }

    const snapshotRuns = snapshot && snapshot.userData && Array.isArray(snapshot.userData.runs)
      ? snapshot.userData.runs
      : [];

    if (!structuredRuns.length) {
      const localUserData = parseJSON(global.localStorage.getItem(USER_DATA_KEY), null);
      const fallbackRuns = snapshotRuns.length
        ? snapshotRuns
        : (localUserData && Array.isArray(localUserData.runs) ? localUserData.runs : []);
      return {
        source: snapshotRuns.length ? 'swiftdata-snapshot-fallback' : 'localstorage-fallback',
        runs: fallbackRuns,
        structuredCount: 0,
        perRunPayloadMatches: 0,
        snapshotFallbackMatches: snapshotRuns.length,
        detailedMatches: snapshotRuns.length,
        detailedCount: snapshotRuns.length
      };
    }

    const payloadRuns = await Promise.all(structuredRuns.map(async (structuredRun) => {
      if (structuredRun.hasPayload === false) return null;
      try {
        return await loadRunPayload(structuredRun.id);
      } catch (error) {
        console.warn('[SwiftData] Payload individuel indisponible pour', structuredRun.id,
          error && error.message ? error.message : error);
        return null;
      }
    }));

    const usedSnapshotIndexes = new Set();
    let perRunPayloadMatches = 0;
    let snapshotFallbackMatches = 0;

    const runs = structuredRuns.map((structuredRun, index) => {
      let detailedRun = payloadRuns[index];

      if (detailedRun) {
        perRunPayloadMatches += 1;
      } else {
        const detailIndex = findDetailedRun(structuredRun, snapshotRuns, usedSnapshotIndexes);
        detailedRun = detailIndex >= 0 ? snapshotRuns[detailIndex] : null;
        if (detailIndex >= 0) {
          usedSnapshotIndexes.add(detailIndex);
          snapshotFallbackMatches += 1;
        }
      }

      return mergeHistoryRun(structuredRun, detailedRun);
    });

    return {
      source: 'swiftdata',
      runs,
      structuredCount: structuredRuns.length,
      perRunPayloadMatches,
      snapshotFallbackMatches,
      snapshotCount: snapshotRuns.length,
      detailedMatches: perRunPayloadMatches + snapshotFallbackMatches,
      detailedCount: perRunPayloadMatches + snapshotFallbackMatches
    };
  }

  // Manual legacy recovery path. This is intentionally not connected to
  // Storage.prototype.setItem anymore.
  async function syncUserData(userData) {
    if (!userData || typeof userData !== 'object') {
      return { syncedRuns: 0, snapshotSaved: false };
    }

    const runs = Array.isArray(userData.runs) ? userData.runs : [];
    for (const run of runs) {
      await saveRun(run);
    }

    return {
      syncedRuns: runs.length,
      snapshotSaved: false,
      sourceOfTruth: 'swiftdata-direct',
      automaticMirror: false
    };
  }

  async function syncFromLocalStorage() {
    const raw = global.localStorage.getItem(USER_DATA_KEY);
    const userData = parseJSON(raw, null);
    if (!userData) {
      return {
        syncedRuns: 0,
        snapshotSaved: false,
        automaticMirror: false,
        reason: 'no-local-user-data'
      };
    }
    const result = await syncUserData(userData);
    console.log('[SwiftData] Récupération manuelle des courses terminée:', result.syncedRuns, 'course(s)');
    return result;
  }

  async function initialImportIfNeeded() {
    const localUserData = parseJSON(global.localStorage.getItem(USER_DATA_KEY), null);
    const localRuns = localUserData && Array.isArray(localUserData.runs)
      ? localUserData.runs
      : [];

    let nativeRuns;
    try {
      nativeRuns = await listRuns();
    } catch (error) {
      console.warn('[SwiftData] Vérification de démarrage impossible; aucune réécriture locale:',
        error && error.message ? error.message : error);
      return {
        imported: false,
        automaticMirror: false,
        reason: 'native-list-failed',
        error: error && error.message ? error.message : String(error)
      };
    }

    if (nativeRuns.length > 0 && nativeRuns.length >= localRuns.length) {
      const result = {
        imported: false,
        automaticMirror: false,
        reason: 'swiftdata-already-populated',
        nativeRuns: nativeRuns.length,
        localRuns: localRuns.length
      };
      console.log('[SwiftData] Démarrage SwiftData-first sans miroir automatique:', result);
      return result;
    }

    if (!localUserData || localRuns.length === 0) {
      const result = {
        imported: false,
        automaticMirror: false,
        reason: 'no-local-history-to-import',
        nativeRuns: nativeRuns.length,
        localRuns: localRuns.length
      };
      console.log('[SwiftData] Démarrage sans import local:', result);
      return result;
    }

    const syncResult = await syncUserData(localUserData);
    const result = {
      imported: true,
      automaticMirror: false,
      reason: nativeRuns.length === 0 ? 'swiftdata-empty' : 'swiftdata-incomplete',
      nativeRunsBefore: nativeRuns.length,
      localRuns: localRuns.length,
      syncedRuns: syncResult.syncedRuns
    };
    console.log('[SwiftData] Import local de récupération effectué:', result);
    return result;
  }

  function startRecoveryCheck() {
    global.setTimeout(function () {
      syncInFlight = syncInFlight
        .then(initialImportIfNeeded)
        .catch(function (error) {
          console.warn('[SwiftData] Vérification initiale ignorée:',
            error && error.message ? error.message : error);
        });
    }, 750);
  }

  global.RunPacerStorage = {
    status,
    saveRun,
    listRuns,
    loadRunPayload,
    deleteRun,
    saveSnapshot,
    loadSnapshot,
    loadHistory,
    syncUserData,
    syncFromLocalStorage,
    initialImportIfNeeded,
    syncNow: syncFromLocalStorage,
    automaticRunMirrorEnabled: false
  };

  startRecoveryCheck();
})(window);