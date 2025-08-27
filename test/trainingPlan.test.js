const { expect } = require('chai');
const { generateWeeklyVolumes, validateLongRun, generateTrainingSchedule } = require('../trainingPlan');

describe('training plan utilities', () => {
  it('applies 10% progression with a 15% deload every 4th week', () => {
    const vols = generateWeeklyVolumes(10, 4);
    expect(vols).to.deep.equal([10, 11, 12, 10]);
  });

  it('validates long runs against safety rules', () => {
    expect(validateLongRun(20, 50, 40)).to.be.false;
    expect(validateLongRun(13, 50, 20, true, 10)).to.be.false;
    expect(validateLongRun(8, 30, 20, true, 8)).to.be.true;
  });

  it('captures user parameters in training schedule', () => {
    const plan = generateTrainingSchedule({ startVolume: 10, weeks: 4, daysAvailable: 4, longRunDay: 'Saturday', tempoOnly: true });
    expect(plan.settings.daysAvailable).to.equal(4);
    expect(plan.settings.longRunDay).to.equal('Saturday');
    expect(plan.settings.tempoOnly).to.be.true;
    expect(plan.weeklyVolumes).to.deep.equal([10, 11, 12, 10]);
  });
});
