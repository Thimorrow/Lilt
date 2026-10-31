import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshFocus, focusSnapshot, focusLocked, focusAction } from '../Resources/Web/focus-state.mjs';
const idle = () => ({ ...freshFocus(), ready: true, restoring: false, phase: 'idle' });
test('UI waits for native state and rejects malformed activity, duration or phase', () => {
  assert.equal(focusLocked(freshFocus()), true);
  assert.equal(focusSnapshot({ ...idle(), activity: 'sleep' }), null);
  assert.equal(focusSnapshot({ ...idle(), duration: 0 }), null);
  assert.equal(focusSnapshot({ ...idle(), remaining: NaN }), null);
  assert.equal(focusSnapshot({ ...idle(), phase: 'optimistic-playing' }), null);
  assert.equal(focusSnapshot({ ...idle(), activity: 'lightWork', duration: 3000 }).ready, true);
});
test('native running, pending and uncertain states lock configuration', () => {
  assert.equal(focusLocked(idle()), false);
  for (const state of [{ phase: 'running' }, { phase: 'uncertain' }, { pending: { id: '1', action: 'start' } }, { restoring: true }]) {
    assert.equal(focusLocked({ ...idle(), ...state }), true);
  }
});
test('owned focus, failures and completion preserve their native state', () => {
  for (const state of [{ owned: true, phase: 'paused' }, { phase: 'running', owned: true }, { pending: { id: '1', action: 'start' } }, { error: { code: 'permission', message: 'Allow access.', action: 'start' } }, { phase: 'completed', remaining: 0 }]) {
    const native = { ...idle(), ...state };
    const snapshot = focusSnapshot(native);
    assert.equal(snapshot.phase, native.phase);
    assert.equal(snapshot.owned, native.owned);
    assert.equal(snapshot.remaining, native.remaining);
    assert.deepEqual(snapshot.pending, native.pending);
    assert.deepEqual(snapshot.error, native.error);
  }
});
test('UI requests native actions, including failed completion retry, without owning a clock', () => {
  assert.equal(focusAction(idle()), 'start');
  assert.equal(focusAction({ ...idle(), phase: 'running' }), 'pause');
  assert.equal(focusAction({ ...idle(), error: { action: 'finish' } }), 'finish');
  const snapshot = focusSnapshot({ ...idle(), remaining: 1234 });
  assert.equal(snapshot.remaining, 1234);
});
