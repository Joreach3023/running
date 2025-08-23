// Boss Run client helpers
(function () {
  async function sendContribution(run, user) {
    try {
      const boss = await getCurrentBoss();
      if (!boss) return;
      await fetch(`/api/boss/${boss.id}/contrib`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          km: parseFloat(run.distance),
          seconds: run.duration,
          userId: user?.id || user?.firstName || 'anon',
          clanId: user?.clanId || null,
          source: 'app',
          runId: run.startTime
        })
      });
    } catch (err) {
      console.error('Boss contribution failed', err);
    }
  }

  async function getCurrentBoss(user) {
    const url = user ? `/api/boss/current?user=${encodeURIComponent(user.id || user.firstName)}` : '/api/boss/current';
    const r = await fetch(url);
    if (!r.ok) return null;
    return r.json();
  }

  function formatTime(sec) {
    const s = Math.max(0, Math.floor(sec));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const rem = s % 60;
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${rem.toString().padStart(2, '0')}`;
  }

  async function refreshBossUI(user) {
    const data = await getCurrentBoss(user);
    if (!data) return;
    const bar = document.getElementById('boss-bar-fill');
    if (bar) {
      const pct = data.hp_total ? (data.hp_remaining / data.hp_total) * 100 : 0;
      bar.style.width = pct + '%';
    }
    const timer = document.getElementById('boss-timer');
    if (timer) timer.textContent = formatTime(data.time_remaining);
    const your = document.getElementById('boss-your');
    if (your) your.textContent = (data.your_contribution || 0).toFixed ? data.your_contribution.toFixed(2) : data.your_contribution;
    const top = document.getElementById('boss-top');
    if (top) {
      if (data.top_contributor) {
        top.textContent = `${data.top_contributor.user}: ${data.top_contributor.km}`;
      } else {
        top.textContent = 'N/A';
      }
    }
  }

  window.RunpacerBoss = { sendContribution, refreshBossUI, getCurrentBoss };
})();
