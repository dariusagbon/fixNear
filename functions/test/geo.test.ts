import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { distanceKm, readLatLng, serviceAreasMatch, serviceRadiusKm } from '../src/geo';

describe('geo', () => {
  it('measures distances in Davao correctly', () => {
    // San Pedro Cathedral to SM Lanang Premier: about 4.6 km.
    const km = distanceKm(
      { latitude: 7.0654, longitude: 125.6076 },
      { latitude: 7.0996, longitude: 125.6317 },
    );
    assert.ok(km > 4.4 && km < 4.8, `got ${km}`);
    assert.equal(distanceKm({ latitude: 7, longitude: 125 }, { latitude: 7, longitude: 125 }), 0);
  });

  it('defaults and clamps the service radius to 2–50 km', () => {
    assert.equal(serviceRadiusKm(undefined), 10);
    assert.equal(serviceRadiusKm('15'), 10);
    assert.equal(serviceRadiusKm(1), 2);
    assert.equal(serviceRadiusKm(80), 50);
    assert.equal(serviceRadiusKm(25), 25);
  });

  it('reads only complete, valid coordinates', () => {
    assert.deepEqual(readLatLng(7.07, 125.61), { latitude: 7.07, longitude: 125.61 });
    assert.equal(readLatLng(7.07, null), null);
    assert.equal(readLatLng(null, null), null);
    assert.equal(readLatLng(95, 125), null);
  });

  it('matches text service areas loosely', () => {
    assert.ok(serviceAreasMatch('Poblacion District, Davao City', 'davao city'));
    assert.ok(serviceAreasMatch('Davao City', 'Davao-City'));
    assert.ok(!serviceAreasMatch('Tagum City', 'Davao City'));
    assert.ok(!serviceAreasMatch('', 'Davao City'));
  });
});
