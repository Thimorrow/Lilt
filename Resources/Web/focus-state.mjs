export const ACTIVITIES = Object.freeze({ deepWork: 'Deep Work', lightWork: 'Light Work' });
export const FOCUS_PHASES = ['idle', 'running', 'paused', 'completed', 'uncertain', 'checking'];
export const freshFocus = () => ({ activity: 'deepWork', duration: 1500, remaining: 1500, deadline: null, phase: 'checking', owned: false, restoring: true, pending: null, error: null, ready: false });
export function focusSnapshot(value) {
  if (!value || !Object.hasOwn(ACTIVITIES, value.activity) || !FOCUS_PHASES.includes(value.phase)
    || !Number.isInteger(value.duration) || value.duration < 60 || value.duration > 10800
    || !Number.isFinite(value.remaining) || value.remaining < 0 || value.remaining > 10800) return null;
  return { ...value, ready: true };
}
export const focusLocked = focus => !focus.ready || Boolean(focus.pending) || focus.phase === 'running' || focus.phase === 'uncertain' || focus.restoring;
export const focusAction = focus => focus.error?.action || (focus.phase === 'running' ? 'pause' : 'start');
