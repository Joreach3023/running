function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Rayon de la Terre en mètres
  const phi1 = lat1 * Math.PI / 180;
  const phi2 = lat2 * Math.PI / 180;
  const deltaPhi = (lat2 - lat1) * Math.PI / 180;
  const deltaLambda = (lon2 - lon1) * Math.PI / 180;

  const a = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
            Math.cos(phi1) * Math.cos(phi2) *
            Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // en mètres
}

if (typeof window !== 'undefined') {
  window.calculateDistance = calculateDistance;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { calculateDistance };
}
