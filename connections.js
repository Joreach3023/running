// connections.js — version sécurisée Strava (Vercel backend)

(() => {
  const API_BASE = "https://runpacer-backend-5rn3i8vbc-jonathan-labbes-projects.vercel.app";

  // --- Stockage centralisé ---
  function getConnections() {
    try {
      return JSON.parse(localStorage.getItem("runPacerConnections")) || {};
    } catch (_) {
      return {};
    }
  }

  function setConnections(obj) {
    localStorage.setItem("runPacerConnections", JSON.stringify(obj || {}));
  }

  function shouldShowOnboarding() {
    const c = getConnections();
    return !c.onboardingShown;
  }

  function setOnboardingShown() {
    const c = getConnections();
    c.onboardingShown = true;
    setConnections(c);
  }

  function saveStravaTokens(data) {
    const c = getConnections();
    c.stravaToken = data.access_token;
    c.stravaRefreshToken = data.refresh_token;
    c.stravaExpiresAt = data.expires_at; // epoch seconds
    // (optionnel) garder l’athlete
    if (data.athlete) c.stravaAthlete = data.athlete;
    setConnections(c);
    // Mets à jour l’UI si tu as un indicateur
    const el = document.getElementById("strava-status");
    if (el) el.textContent = "Connecté ✅";
  }

  function clearStravaTokens() {
    const c = getConnections();
    delete c.stravaToken;
    delete c.stravaRefreshToken;
    delete c.stravaExpiresAt;
    delete c.stravaAthlete;
    setConnections(c);
    const el = document.getElementById("strava-status");
    if (el) el.textContent = "Déconnecté";
  }

  // --- Backend Vercel ---
  async function exchangeCodeOnServer(code) {
    const r = await fetch(`${API_BASE}/api/strava-token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code })
    });
    if (!r.ok) throw new Error("Token exchange failed");
    return r.json(); // { access_token, refresh_token, expires_at, athlete, ... }
  }

  async function refreshOnServer(refresh_token) {
    const r = await fetch(`${API_BASE}/api/strava-refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token })
    });
    if (!r.ok) throw new Error("Refresh failed");
    return r.json(); // { access_token, refresh_token, expires_at, ... }
  }

  // --- Gestion de validité du token ---
  async function ensureValidToken() {
    const c = getConnections();
    const now = Math.floor(Date.now() / 1000);
    if (!c.stravaToken || !c.stravaExpiresAt) return null;

    if (now >= (c.stravaExpiresAt - 60)) {
      // Refresh
      if (!c.stravaRefreshToken) return null;
      const nd = await refreshOnServer(c.stravaRefreshToken);
      saveStravaTokens(nd);
      return nd.access_token;
    }
    return c.stravaToken;
  }

  // --- Connexion / Déconnexion ---
  function buildStravaAuthUrl() {
    const base = (typeof isIOSCapacitor !== "undefined" && isIOSCapacitor)
      ? "https://www.strava.com/oauth/mobile/authorize"
      : "https://www.strava.com/oauth/authorize";

    const params = new URLSearchParams({
      client_id: String(STRAVA_CLIENT_ID),
      redirect_uri: STRAVA_REDIRECT_URI,        // défini dans index.html (iOS vs Web)
      response_type: "code",
      approval_prompt: "auto",
      scope: "read,activity:read,activity:write" // adapte si besoin
    });
    return `${base}?${params.toString()}`;
  }

  async function connectStrava() {
    const url = buildStravaAuthUrl();

    // iOS: ouvrir dans Capacitor Browser, Web: rediriger
    if (typeof isIOSCapacitor !== "undefined" && isIOSCapacitor && window.Capacitor?.Plugins?.Browser) {
      await window.Capacitor.Plugins.Browser.open({ url, presentationStyle: "popover" });
    } else {
      window.location.href = url;
    }
  }

  function disconnectStrava() {
    clearStravaTokens();
    alert("Compte Strava déconnecté.");
  }

  // --- (Optionnel ici) Listener iOS pour récupérer le deep link ---
  // Si tu l’as déjà mis dans index.html, tu peux supprimer ce bloc.
  if (window.Capacitor?.Plugins?.App && window.Capacitor?.Plugins?.Browser) {
    window.Capacitor.Plugins.App.addListener("appUrlOpen", async ({ url }) => {
      try {
        if (!url || !url.startsWith("runpacer://")) return;
        try { await window.Capacitor.Plugins.Browser.close(); } catch (_) {}
        const code = new URL(url).searchParams.get("code");
        if (!code) return;
        const tokens = await exchangeCodeOnServer(code);
        saveStravaTokens(tokens);
        // Feedback utilisateur
        const el = document.getElementById("strava-status");
        if (el) el.textContent = "Connecté ✅";
      } catch (e) {
        console.error("appUrlOpen error", e);
        alert("Erreur de connexion Strava. Réessaie.");
      }
    });
  }

  // --- API publique pour le reste de l’app ---
  window.RunpacerConnections = {
    connectStrava,
    disconnectStrava,
    ensureValidToken,
    // utilitaires si besoin
    saveStravaTokens,
    getConnections,
    shouldShowOnboarding,
    setOnboardingShown
  };
})();
