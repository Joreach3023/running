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

// Build one training week with two run sessions separated by 48h
function buildWeek(start, totalRunMinutes) {
  const per = Math.round(totalRunMinutes / 2);
  const sessions = [
    {
      date: addDays(start, 0),
      type: "run",
      minutes: per,
      rpe: 3,
      tags: ["#Postpartum", "#ReturnToRun", "RPE3-4"],
    },
    {
      date: addDays(start, 2),
      type: "run",
      minutes: per,
      rpe: 3,
      tags: ["#Postpartum", "#ReturnToRun", "RPE3-4"],
    },
  ];
  return { start, sessions, totalRunMinutes: per * 2 };
}

function createPlan(start, startingTotal) {
  const weeks = [];
  let total = startingTotal;
  for (let i = 0; i < 4; i++) {
    const wStart = addDays(start, i * 7);
    weeks.push(buildWeek(wStart, total));
    total = Math.round(total * 1.1); // +10%
  }
  return weeks;
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
  const status = evaluateReadiness(pp);
  if (status === "Stop") return { status, weeks: [] };
  if (status === "DeferToWalkPelvic") {
    return { status: "Defer", weeks: createWalkPelvicPlan(start) };
  }
  if (pp.weeksPostpartum < 12) {
    return { status: "OK", weeks: createPlan(start, 20) }; // phase2-like
  }
  // phase3
  const startTotal = pp.goal === "run_30min" ? 40 : 20;
  return { status: "OK", weeks: createPlan(start, startTotal) };
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

module.exports = { evaluateReadiness, generatePostpartumPlan, applySymptoms };
