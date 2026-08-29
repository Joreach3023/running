// RunPacer one-way personal data migration: Supabase -> SwiftData
//
// Safety properties:
// - Read-only against Supabase.
// - Idempotent: RunPacerStorage.saveRun upserts by UUID.
// - Does NOT delete or modify Supabase data.
// - Supports both legacy device_id profiles and newer auth_uid profiles.
//
// Usage (after the live web source is restored/versioned):
//   await RunPacerSupabaseMigration.migrate({
//     supabaseClient,
//     authUserId: session?.user?.id,
//     deviceId: currentDeviceId
//   });

(function (global) {
  const MIGRATION_VERSION = 1;

  function assertReady(supabaseClient) {
    if (!supabaseClient || typeof supabaseClient.from !== 'function') {
      throw new Error('A valid Supabase client is required');
    }
    if (!global.RunPacerStorage) {
      throw new Error('RunPacerStorage bridge is required');
    }
  }

  async function findProfileIds(supabaseClient, { authUserId, deviceId }) {
    const ids = new Set();

    if (authUserId) {
      const { data, error } = await supabaseClient
        .from('profiles')
        .select('id')
        .eq('auth_uid', authUserId);
      if (error) throw error;
      (data || []).forEach((row) => row && row.id && ids.add(row.id));
    }

    if (deviceId) {
      const { data, error } = await supabaseClient
        .from('profiles')
        .select('id')
        .eq('device_id', deviceId);
      if (error) throw error;
      (data || []).forEach((row) => row && row.id && ids.add(row.id));
    }

    return Array.from(ids);
  }

  async function fetchRuns(supabaseClient, profileIds) {
    if (!profileIds.length) return [];

    const { data, error } = await supabaseClient
      .from('runs')
      .select('id,name,distance_km,duration_secs,date,type,source,notes,created_at,profile_id')
      .in('profile_id', profileIds)
      .order('date', { ascending: true });

    if (error) throw error;
    return data || [];
  }

  async function fetchBackup(supabaseClient, authUserId) {
    if (!authUserId) return null;

    const { data, error } = await supabaseClient
      .from('user_backups')
      .select('user_data,training_plan,device_id,updated_at')
      .eq('user_id', authUserId)
      .maybeSingle();

    if (error) throw error;
    return data || null;
  }

  async function importRuns(runs) {
    let imported = 0;

    for (const run of runs) {
      await global.RunPacerStorage.saveRun({
        id: run.id,
        name: run.name || 'Course',
        distanceKm: Number(run.distance_km || 0),
        durationSecs: run.duration_secs == null ? undefined : Number(run.duration_secs),
        date: run.date || run.created_at,
        type: run.type || 'Run',
        source: run.source || 'runpacer',
        notes: run.notes || undefined,
        createdAt: run.created_at || run.date
      });
      imported += 1;
    }

    return imported;
  }

  async function importBackup(backup, fallbackDeviceId) {
    if (!backup) return false;

    await global.RunPacerStorage.saveSnapshot({
      userData: backup.user_data || null,
      trainingPlan: backup.training_plan || null,
      deviceId: backup.device_id || fallbackDeviceId || null
    });
    return true;
  }

  async function verifyRuns(sourceRuns) {
    const localRuns = await global.RunPacerStorage.listRuns();
    const localIds = new Set((localRuns || []).map((run) => run.id));
    const missingIds = sourceRuns
      .map((run) => run.id)
      .filter((id) => id && !localIds.has(id));

    return {
      localCount: localRuns.length,
      sourceCount: sourceRuns.length,
      missingIds,
      ok: missingIds.length === 0
    };
  }

  async function migrate({ supabaseClient, authUserId = null, deviceId = null } = {}) {
    assertReady(supabaseClient);

    const storageStatus = await global.RunPacerStorage.status();
    if (!storageStatus.available || !storageStatus.persistent) {
      throw new Error(
        storageStatus.fallbackReason || 'Persistent SwiftData storage is unavailable'
      );
    }

    const profileIds = await findProfileIds(supabaseClient, { authUserId, deviceId });
    if (!profileIds.length && !authUserId) {
      throw new Error('No matching Supabase profile was found for this device');
    }

    const [runs, backup] = await Promise.all([
      fetchRuns(supabaseClient, profileIds),
      fetchBackup(supabaseClient, authUserId)
    ]);

    const runsImported = await importRuns(runs);
    const backupImported = await importBackup(backup, deviceId);
    const verification = await verifyRuns(runs);

    if (!verification.ok) {
      throw new Error(
        `SwiftData verification failed: ${verification.missingIds.length} run(s) missing`
      );
    }

    const result = {
      version: MIGRATION_VERSION,
      completedAt: new Date().toISOString(),
      profileIds,
      runsImported,
      backupImported,
      verification
    };

    try {
      localStorage.setItem('runPacerSwiftDataMigrationV1', JSON.stringify(result));
    } catch (_) {
      // Migration success must not depend on localStorage availability.
    }

    return result;
  }

  global.RunPacerSupabaseMigration = {
    version: MIGRATION_VERSION,
    findProfileIds,
    migrate
  };
})(window);
