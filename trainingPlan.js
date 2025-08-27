const GENERAL_RECOMMENDATIONS = "Au moins 150 min/sem d'activité modérée pendant le post-partum et reprise progressive de la course à partir de 12 semaines en l'absence de symptômes.";

function generateWeeklyVolumes(startVolume, weeks = 4) {
  const volumes = [];
  let current;
  for (let w = 0; w < weeks; w++) {
    if (w === 0) {
      current = Math.round(startVolume);
    } else if ((w + 1) % 4 === 0) {
      current = Math.round(volumes[w - 1] * 0.85);
    } else {
      current = Math.round(volumes[w - 1] * 1.1);
    }
    volumes.push(current);
  }
  return volumes;
}

function validateLongRun(plannedKm, weeklyVolumeKm, currentWeeklyKm, isFirst = false, previousLongRunKm = 0) {
  if (plannedKm > weeklyVolumeKm * 0.35) return false;
  if (isFirst && plannedKm > Math.max(previousLongRunKm, currentWeeklyKm * 0.35)) return false;
  return true;
}

function generateTrainingSchedule({ startVolume, weeks = 4, daysAvailable = 3, longRunDay = 'Sunday', tempoOnly = false }) {
  return {
    settings: { daysAvailable, longRunDay, tempoOnly },
    weeklyVolumes: generateWeeklyVolumes(startVolume, weeks)
  };
}

module.exports = { generateWeeklyVolumes, validateLongRun, generateTrainingSchedule, GENERAL_RECOMMENDATIONS };
