import test from 'node:test';
import assert from 'node:assert/strict';
import { notificationBanner } from '../Resources/Web/notification-banner.mjs';
import { freshSettings, settingsSnapshot } from '../Resources/Web/settings-state.mjs';

const fixture = { id: '12345678-1234-1234-1234-123456789012', source: 'Synthetic', title: '<img onerror=alert(1)>', body: 'Plaintext' };
test('notification boundary bounds plaintext and rejects malformed values', () => {
  assert.equal(notificationBanner(fixture).title, fixture.title);
  assert.equal(notificationBanner({ ...fixture, body: 'b'.repeat(1000) }).body.length, 360);
  assert.equal(notificationBanner({ ...fixture, source: 's'.repeat(1000) }).source.length, 80);
  assert.equal(notificationBanner({ ...fixture, title: 'x\u0000y' }).title, 'xy');
  for (const value of [null, {}, { ...fixture, title: 1 }, { ...fixture, id: 'bad' }]) assert.equal(notificationBanner(value), null);
});
test('notification settings default off and validate snapshots without breaking older snapshots', () => {
  const state = freshSettings();
  assert.equal(state.notificationBannersEnabled, false);
  assert.equal(settingsSnapshot(state).notificationBannersEnabled, false);
  const older = { ...state };
  delete older.notificationBannersEnabled;
  delete older.notificationCaptureStatus;
  delete older.notificationCaptureMessage;
  assert.equal(settingsSnapshot(older).notificationBannersEnabled, false);
  assert.equal(settingsSnapshot({ ...state, notificationBannersEnabled: 1 }), null);
  assert.equal(settingsSnapshot({ ...state, notificationCaptureStatus: 'ready' }), null);
  assert.equal(settingsSnapshot({ ...state, notificationCaptureMessage: {} }), null);
});
