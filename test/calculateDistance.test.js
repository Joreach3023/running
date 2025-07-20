const fs = require('fs');
const path = require('path');
const { expect } = require('chai');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const match = html.match(/function\s+calculateDistance\([^)]*\)\s*{[\s\S]*?}/);
if (!match) {
  throw new Error('calculateDistance function not found in index.html');
}
// Evaluate the function definition to make calculateDistance available
// eslint-disable-next-line no-eval
eval(match[0]);

describe('calculateDistance', () => {
  it('returns distance between Paris and London within tolerance', () => {
    const paris = { lat: 48.8566, lon: 2.3522 };
    const london = { lat: 51.5074, lon: -0.1278 };
    const result = calculateDistance(paris.lat, paris.lon, london.lat, london.lon);
    expect(result).to.be.closeTo(343556, 1000); // ~343 km
  });
});
