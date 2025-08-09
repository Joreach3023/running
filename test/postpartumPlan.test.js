const { expect } = require('chai');
const { generatePostpartumPlan, applySymptoms } = require('../postpartum');

describe('postpartum plan generator', () => {
  it('6 weeks with medical clearance -> running plan phase2', () => {
    const profile = {
      enabled: true,
      weeksPostpartum: 6,
      deliveryType: 'vaginal',
      symptoms: {
        leakage: false,
        heaviness: false,
        painAbdominalBack: false,
        diastasisSuspected: false,
        incisionPain: false,
        abnormalBleeding: false,
      },
      activityLevel: 'sedentary',
      goal: 'run_5k_comfort',
      medicalCleared: true,
    };
    const start = new Date('2024-01-01');
    const plan = generatePostpartumPlan(profile, start);
    expect(plan.status).to.equal('OK');
    expect(plan.weeks[0].sessions).to.have.lengthOf(2);
    const [s1, s2] = plan.weeks[0].sessions;
    expect(s1.rpe).to.be.within(3, 4);
    expect(s2.rpe).to.be.within(3, 4);
    const diffDays = (s2.date - s1.date) / (1000 * 60 * 60 * 24);
    expect(diffDays).to.be.at.least(2); // 48h rest
    for (let i = 1; i < plan.weeks.length; i++) {
      const prev = plan.weeks[i - 1].totalRunMinutes;
      const curr = plan.weeks[i].totalRunMinutes;
      expect(curr).to.be.at.most(prev * 1.15 + 0.1);
    }
  });

  it('10 weeks without medical clearance -> walk + pelvic plan', () => {
    const profile = {
      enabled: true,
      weeksPostpartum: 10,
      deliveryType: 'vaginal',
      symptoms: {
        leakage: false,
        heaviness: false,
        painAbdominalBack: false,
        diastasisSuspected: false,
        incisionPain: false,
        abnormalBleeding: false,
      },
      activityLevel: 'sedentary',
      goal: 'run_5k_comfort',
      medicalCleared: false,
    };
    const start = new Date('2024-01-01');
    const plan = generatePostpartumPlan(profile, start);
    expect(plan.status).to.equal('Defer');
    expect(plan.weeks).to.have.lengthOf(2);
    expect(plan.weeks[0].sessions[0].type).to.equal('walk');
  });

  it('symptom feedback regresses next weeks by -10%', () => {
    const profile = {
      enabled: true,
      weeksPostpartum: 16,
      deliveryType: 'vaginal',
      symptoms: {
        leakage: false,
        heaviness: false,
        painAbdominalBack: false,
        diastasisSuspected: false,
        incisionPain: false,
        abnormalBleeding: false,
      },
      activityLevel: 'sedentary',
      goal: 'run_30min',
      medicalCleared: true,
    };
    const start = new Date('2024-01-01');
    const plan = generatePostpartumPlan(profile, start);
    const firstWeek = plan.weeks[0].totalRunMinutes;
    applySymptoms(plan, 2); // symptoms after week1 session2 -> adjust from week2
    expect(plan.weeks[1].totalRunMinutes).to.be.closeTo(firstWeek * 0.9, 0.1);
    const diffDays = (plan.weeks[1].sessions[1].date - plan.weeks[1].sessions[0].date) / (1000 * 60 * 60 * 24);
    expect(diffDays).to.be.at.least(2);
  });
});
