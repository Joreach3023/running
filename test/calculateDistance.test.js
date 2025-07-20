const { expect } = require('chai');
const { calculateDistance } = require('../utils');

describe('calculateDistance', () => {
  it('returns distance between Paris and London within tolerance', () => {
    const paris = { lat: 48.8566, lon: 2.3522 };
    const london = { lat: 51.5074, lon: -0.1278 };
    const result = calculateDistance(paris.lat, paris.lon, london.lat, london.lon);
    expect(result).to.be.closeTo(343556, 1000); // ~343 km
  });
});
