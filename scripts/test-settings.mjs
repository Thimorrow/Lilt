import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshSettings, settingsSnapshot, providerState, shownValue, menuOptions, durationValue, retentionValue } from '../Resources/Web/settings-state.mjs';

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

test('shelf retention validates saved settings and accepts whole days only', () => {
  assert.equal(settingsSnapshot(snapshot({ shelfShortDays: 7, shelfLongDays: 30 })).shelfLongDays, 30);
  for (const invalid of [0, 3651, 1.5, '7', null]) {
    assert.equal(settingsSnapshot(snapshot({ shelfShortDays: invalid })), null);
    assert.equal(settingsSnapshot(snapshot({ shelfLongDays: invalid })), null);
  }
  for (const raw of ['', ' ', '0', '-1', '3651', '1.2', 'NaN', 'Infinity']) assert.equal(retentionValue(raw), null);
  assert.equal(retentionValue('1'), 1);
  assert.equal(retentionValue('3650'), 3650);
  assert.equal(retentionValue(' 30 '), 30);
});

test('display choices come from validated native snapshot', () => {
  assert.equal(settingsSnapshot(snapshot({ displayID: false })), null);
  assert.equal(settingsSnapshot(snapshot({ displays: null })), null);
  const value = settingsSnapshot(snapshot({ displayID: 'a', displayUnavailable: true, displays: [{ id: 'a', name: 'Monitor' }, { id: 12, name: 'Invalid' }] }));
  assert.equal(value.displayUnavailable, true);
  assert.deepEqual(value.displays, [{ id: 'a', name: 'Monitor' }]);
});

test('requested values show optimistically and fall back to the native value', () => {
  const state = { ...freshSettings(), brainFMEnabled: false };
  assert.equal(shownValue(state, { brainFMEnabled: true }, 'brainFMEnabled'), true);
  assert.equal(shownValue(state, { focusMinutes: 50 }, 'brainFMEnabled'), false);
  assert.equal(shownValue(state, null, 'brainFMEnabled'), false);
});

test('menus keep custom and disconnected values selectable', () => {
  const state = { ...freshSettings(), shelfShortDays: 45, displayID: 'gone', displays: [{ id: 'a', name: 'Monitor' }] };
  assert.deepEqual(menuOptions('shelfShortDays', state).map(option => option.value), [1, 3, 7, 14, 30, 45]);
  assert.equal(menuOptions('shelfLongDays', { ...state, shelfLongDays: 30 }).filter(option => option.value === 30).length, 1);
  assert.deepEqual(menuOptions('displayID', state), [{ value: '', label: 'Automatic' }, { value: 'a', label: 'Monitor' }, { value: 'gone', label: 'Disconnected display' }]);
});
