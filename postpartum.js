/**
 * Utilities for postpartum return-to-running plans.
 * The implementation is intentionally simple and aims to respect
 * safety rules: readiness evaluation, 48h rest, and <=15% weekly progression.
 */

// Helper to add days to a date
function addDays(date, days) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

/**
 * Evaluate readiness for running after pregnancy.
 * @param {Object} pp - PostpartumProfile-like object
 * @returns {"OK"|"DeferToWalkPelvic"|"Stop"}
 */
function evaluateReadiness(pp) {
  const crit = pp.symptoms?.abnormalBleeding || pp.symptoms?.incisionPain;
  if (crit) return "Stop";
  const light = pp.symptoms?.leakage || pp.symptoms?.heaviness ||
    pp.symptoms?.painAbdominalBack || pp.symptoms?.diastasisSuspected;
  if (pp.weeksPostpartum < 12 && !pp.medicalCleared) return "DeferToWalkPelvic";
  if (light) return "DeferToWalkPelvic";
  return "OK";
}

// Determine starting total run minutes based on profile
function getStartingTotal(pp) {
  if (pp.goal === "run_30min") return 40;
  switch (pp.activityLevel) {
    case "active":
      return 30;
    case "moderate":
      return 25;
    default:
      return 20;
  }
}

// Default paces (minutes per km)
const RUN_PACE = 7;
const REST_PACE = 12;

// Helper to build a session with run/rest intervals
function buildSession(date, type, runMin, restMin) {
  const distance = runMin / RUN_PACE + restMin / REST_PACE;
  return {
    date,
    type,
    runMinutes: runMin,
    restMinutes: restMin,
    minutes: runMin + restMin,
    rpe: 3,
    distanceKm: Number(distance.toFixed(2)),
    paceRun: RUN_PACE,
    paceRest: REST_PACE,
    tags: ["#Postpartum", "#ReturnToRun", "RPE3-4"],
  };
}

// Build one training week with two interval sessions separated by 48h
function buildWeek(start, totalRunMinutes) {
  const run1 = Math.round(totalRunMinutes * 0.4);
  const run2 = totalRunMinutes - run1;
  const rest1 = Math.round(run1 * 0.5);
  const rest2 = Math.round(run2 * 0.25);
  const sessions = [
    buildSession(addDays(start, 0), "interval_easy", run1, rest1),
    buildSession(addDays(start, 2), "interval_long", run2, rest2),
  ];
  return { start, sessions, totalRunMinutes: run1 + run2 };
}

const { generateWeeklyVolumes, GENERAL_RECOMMENDATIONS } = require('./trainingPlan');

function createPlan(start, startingTotal, weeks = 4) {
  const volumes = generateWeeklyVolumes(startingTotal, weeks);
  const planWeeks = [];
  for (let i = 0; i < weeks; i++) {
    const wStart = addDays(start, i * 7);
    planWeeks.push(buildWeek(wStart, volumes[i]));
  }
  return planWeeks;
}

function createWalkPelvicPlan(start, weeks = 2) {
  const plan = [];
  for (let i = 0; i < weeks; i++) {
    const wStart = addDays(start, i * 7);
    const sessions = [
      { date: addDays(wStart, 0), type: "walk", minutes: 30 },
      { date: addDays(wStart, 2), type: "pelvic", minutes: 0 },
    ];
    plan.push({ start: wStart, sessions, totalRunMinutes: 0 });
  }
  return plan;
}

/**
 * Generate a postpartum running plan.
 * @param {Object} pp - profile
 * @param {Date} start - starting date
 * @returns {Object} plan
 */
function generatePostpartumPlan(pp, start) {
  const recommendations = GENERAL_RECOMMENDATIONS;
  const status = evaluateReadiness(pp);
  if (status === "Stop") return { status, weeks: [], warning: "Symptômes nécessitant l'arrêt", recommendations };
  if (status === "DeferToWalkPelvic") {
    return { status: "Defer", weeks: createWalkPelvicPlan(start), warning: "Reprise différée : marche + renforcement pelvien", recommendations };
  }
  const startTotal = getStartingTotal(pp);
  let weeks;
  if (pp.weeksPostpartum < 12) {
    weeks = createPlan(start, Math.min(20, startTotal)); // phase2-like
  } else {
    weeks = createPlan(start, startTotal);
  }
  return { status: "OK", weeks, recommendations };
}

/**
 * Regress the plan if symptoms appear.
 * Repeats previous week with -10% volume then continues progression.
 * @param {Object} plan
 * @param {number} weekNumber - 1-based week index to adjust from
 * @returns {Object} updated plan
 */
function applySymptoms(plan, weekNumber) {
  const idx = weekNumber - 1;
  if (!plan?.weeks || idx <= 0 || idx >= plan.weeks.length) return plan;
  const prev = plan.weeks[idx - 1].totalRunMinutes;
  let total = Math.round(prev * 0.9);
  for (let i = idx; i < plan.weeks.length; i++) {
    const start = plan.weeks[i].start;
    plan.weeks[i] = buildWeek(start, total);
    total = Math.round(total * 1.1);
  }
  return plan;
}

const api = { evaluateReadiness, generatePostpartumPlan, applySymptoms };

// Support both Node.js and browser environments
if (typeof module !== 'undefined' && module.exports) {
  module.exports = api;
} else if (typeof window !== 'undefined') {
  window.Postpartum = api;
}
