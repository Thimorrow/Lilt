import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshFocus, focusSnapshot, focusLocked, focusPriority, focusAction } from '../Resources/Web/focus-state.mjs';
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
test('active focus, failures and completion stay visible across other selected tabs', () => {
  assert.equal(focusPriority(idle()), false);
  for (const state of [{ owned: true, phase: 'paused' }, { phase: 'running', owned: true }, { pending: { action: 'start' } }, { error: { code: 'permission' } }, { phase: 'completed' }]) {
    assert.equal(focusPriority({ ...idle(), ...state }), true);
  }
});
test('UI requests native actions, including failed completion retry, without owning a clock', () => {
  assert.equal(focusAction(idle()), 'start');
  assert.equal(focusAction({ ...idle(), phase: 'running' }), 'pause');
  assert.equal(focusAction({ ...idle(), error: { action: 'finish' } }), 'finish');
  const snapshot = focusSnapshot({ ...idle(), remaining: 1234 });
  assert.equal(snapshot.remaining, 1234);
});
