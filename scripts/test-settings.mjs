import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshSettings, settingsSnapshot, providerState, durationValue } from '../Resources/Web/settings-state.mjs';

const snapshot = extra => ({ ...freshSettings(), saved: true, ...extra });

test('settings reject invalid native configuration and preserve confirmed values', () => {
  for (const invalid of [{ musicSource: 'global' }, { brainFMEnabled: 'false' }, { focusMinutes: 0 }, { focusMinutes: 181 }, { focusMinutes: 1.5 }, { focusActivity: 'sleep' }, { focusLocked: null }, { brainFM: {} }, { error: { message: 'no code' } }]) {
    assert.equal(settingsSnapshot(snapshot(invalid)), null);
  }
  const confirmed = settingsSnapshot(snapshot({ musicSource: 'appleMusic', focusMinutes: 180, brainFMEnabled: false }));
  assert.equal(confirmed.musicSource, 'appleMusic');
  assert.equal(confirmed.focusMinutes, 180);
  assert.equal(confirmed.brainFMEnabled, false);
  assert.equal(confirmed.ready, true);
});

test('source installation, process and permission states expose appropriate recovery actions', () => {
  const provider = extra => ({ id: 'spotify', installed: true, running: true, availability: 'ready', ...extra });
  assert.deepEqual(providerState(provider({ installed: false })), { status: 'missing', label: 'Not installed', connect: false, open: false });
  assert.equal(providerState(provider({ running: false })).connect, false);
  assert.equal(providerState(provider({ running: false })).open, true);
  assert.equal(providerState(provider({ availability: 'permission' })).connect, true);
  assert.equal(providerState(provider({ availability: 'empty' })).status, 'ready');
  assert.equal(providerState(provider({ availability: 'disabled' })).open, false);
  assert.equal(providerState(null).connect, false);
});

test('unknown or malformed providers do not become selectable sources', () => {
  const native = settingsSnapshot(snapshot({ providers: [
    { id: 'spotify', installed: true, running: false, availability: 'offline' },
    { id: 'unknown', installed: true, running: true, availability: 'ready' },
    { id: 'appleMusic', installed: 'yes', running: true, availability: 'ready' },
  ] }));
  assert.equal(native.providers.length, 1);
  assert.equal(native.providers[0].id, 'spotify');
});

test('custom durations accept only whole minutes in the supported range', () => {
  for (const raw of ['', ' ', '0', '-1', '181', '1.2', 'NaN', 'Infinity', 'twenty']) assert.equal(durationValue(raw), null);
  assert.equal(durationValue('1'), 1);
  assert.equal(durationValue('180'), 180);
  assert.equal(durationValue(' 25 '), 25);
});
