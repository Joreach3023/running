// RunPacer native personal-storage bridge (Capacitor 7 / iOS 17+)
//
// This file is intentionally dependency-free so the current RunPacer web app
// can use it without a JS bundler. When the current web source is restored to
// version control, include this file after Capacitor has initialized.

(function (global) {
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

  async function status() {
    const plugin = await requirePlugin();
    return plugin.status();
  }

  async function saveRun(run) {
    const plugin = await requirePlugin();
    return plugin.saveRun({
      id: run.id || undefined,
      name: run.name || 'Course',
      distanceKm: Number(run.distanceKm ?? run.distance ?? 0),
      durationSecs: run.durationSecs ?? run.duration ?? undefined,
      date: run.date || run.startTime || new Date().toISOString(),
      type: run.type || 'Run',
      source: run.source || 'runpacer',
      notes: run.notes || undefined,
      createdAt: run.createdAt || run.startTime || run.date || new Date().toISOString()
    });
  }

  async function listRuns() {
    const plugin = await requirePlugin();
    const result = await plugin.listRuns();
    return result.runs || [];
  }

  async function deleteRun(id) {
    const plugin = await requirePlugin();
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

  global.RunPacerStorage = {
    status,
    saveRun,
    listRuns,
    deleteRun,
    saveSnapshot,
    loadSnapshot
  };
})(window);
