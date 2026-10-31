import { MUSIC_SOURCES, SETTINGS_SECTIONS, freshSettings, settingsSnapshot, providerState, durationValue } from './settings-state.mjs';

const root = document.documentElement;
const media = matchMedia('(prefers-reduced-motion: reduce)');
const errors = [];
let state = freshSettings();
let section = 'music';
let requested = null;
let requestTimer;
let localError = null;
let durationDirty = false;
let keyboardUpdate = false;
let pendingFocus = null;
const find = selector => document.querySelector(selector);
const all = selector => [...document.querySelectorAll(selector)];
const native = body => window.webkit?.messageHandlers?.lilt?.postMessage(body);
const reduced = () => media.matches || root.classList.contains('reduce-motion');
const text = (selector, value) => { const element = find(selector); if (element.textContent !== value) element.textContent = value; };
const announce = value => text('[data-announce]', value);
window.addEventListener('error', event => errors.push(event.message));
window.addEventListener('unhandledrejection', event => errors.push(String(event.reason)));

function instant(change) {
  root.classList.add('instant');
  change();
  void root.offsetWidth;
  root.classList.remove('instant');
}

function setSection(next, { focus = false, animate = true } = {}) {
  if (!SETTINGS_SECTIONS.includes(next)) return;
  const apply = () => {
    section = next;
    find('.settings-nav').style.setProperty('--nav-index', SETTINGS_SECTIONS.indexOf(next));
    all('[data-section]').forEach(button => {
      const selected = button.dataset.section === next;
      button.setAttribute('aria-selected', String(selected));
      button.tabIndex = selected ? 0 : -1;
      if (selected && focus) button.focus({ preventScroll: true });
    });
    all('.settings-section').forEach(panel => {
      const selected = panel.id === `settings-${next}`;
      panel.dataset.active = String(selected);
      panel.inert = !selected;
      panel.setAttribute('aria-hidden', String(!selected));
    });
    find('.section-stack').scrollTop = 0;
  };
  if (!animate || reduced()) instant(apply); else apply();
}

function sendChanges(changes, { keyboard = false } = {}) {
  if (!state.ready || requested) return;
  if (Object.keys(changes).some(key => key === 'musicSource' ? state.musicBusy : state.focusLocked)) return;
  if (Object.entries(changes).every(([key, value]) => state[key] === value)) return;
  localError = null;
  requested = changes;
  keyboardUpdate = keyboard;
  pendingFocus = keyboard ? Object.hasOwn(changes, 'musicSource') ? `[data-source="${changes.musicSource}"]` : Object.hasOwn(changes, 'focusActivity') ? `[data-activity="${changes.focusActivity}"]` : Object.hasOwn(changes, 'brainFMEnabled') ? '#brainfm-toggle' : '#default-minutes' : null;
  render();
  native({ action: 'settingsUpdate', changes });
  clearTimeout(requestTimer);
  requestTimer = setTimeout(() => {
    if (!requested) return;
    requested = null;
    localError = 'Lilt did not confirm the change. Try again.';
    keyboardUpdate = false;
    pendingFocus = null;
    render();
    announce(localError);
  }, 8000);
}

function renderMusic() {
  const selected = state.musicSource;
  const disabled = !state.ready || state.musicBusy || Boolean(requested);
  find('.player-picker').style.setProperty('--source-index', Object.keys(MUSIC_SOURCES).indexOf(selected));
  all('[data-source]').forEach(button => {
    const checked = button.dataset.source === selected;
    button.setAttribute('aria-checked', String(checked));
    button.tabIndex = checked ? 0 : -1;
    button.disabled = disabled;
    button.classList.toggle('is-pending', requested?.musicSource === button.dataset.source);
  });
  const provider = state.providers.find(value => value.id === selected);
  const connection = providerState(provider);
  text('[data-provider-name]', MUSIC_SOURCES[selected]);
  find('[data-provider-icon]').setAttribute('href', `#s-${selected}`);
  find('.connection-status').dataset.status = connection.status;
  text('[data-provider-status]', connection.label);
  const message = typeof provider?.message === 'string' ? provider.message : '';
  text('[data-provider-message]', message);
  find('[data-provider-message]').hidden = !message || message === connection.label;
  const connect = find('[data-action="music-connect"]');
  connect.hidden = !connection.connect;
  connect.disabled = disabled;
  connect.firstChild.textContent = connection.status === 'permission' ? 'Allow connection' : 'Connect';
  const open = find('[data-action="music-open"]');
  open.disabled = disabled || !connection.open;
  open.firstChild.textContent = `Open ${MUSIC_SOURCES[selected]}`;
  open.classList.toggle('primary', !connection.connect && connection.open);
  open.classList.toggle('secondary', connection.connect || !connection.open);
  find('.connection-actions').hidden = !connection.open && !connection.connect;
  find('[data-music-busy]').hidden = !state.musicBusy;
}

function renderFocus() {
  const disabled = !state.ready || state.focusLocked || Boolean(requested);
  const input = find('#default-minutes');
  if (!durationDirty || requested?.focusMinutes === state.focusMinutes) input.value = state.focusMinutes;
  input.disabled = disabled;
  find('.duration-apply').disabled = disabled;
  find('.duration-apply').hidden = !durationDirty;
  all('[data-minutes]').forEach(button => {
    button.setAttribute('aria-pressed', String(Number(button.dataset.minutes) === state.focusMinutes));
    button.disabled = disabled;
  });
  find('.activity-picker').style.setProperty('--activity-index', state.focusActivity === 'lightWork' ? 1 : 0);
  all('[data-activity]').forEach(button => {
    const checked = button.dataset.activity === state.focusActivity;
    button.setAttribute('aria-checked', String(checked));
    button.tabIndex = checked ? 0 : -1;
    button.disabled = disabled;
  });
  const toggle = find('#brainfm-toggle');
  toggle.setAttribute('aria-checked', String(state.brainFMEnabled));
  toggle.disabled = disabled;
  text('[data-brainfm-caption]', state.brainFMEnabled ? 'Music follows your timer' : 'Optional focus music');
  const detail = find('[data-brainfm-detail]');
  detail.hidden = !state.brainFMEnabled;
  const brainFM = state.brainFM;
  text('[data-brainfm-message]', !brainFM.installed ? 'Install the Brain.fm Mac app to use focus music.' : !brainFM.permission ? 'Allow Lilt in Accessibility to control Brain.fm.' : 'Brain.fm is ready.');
  const permission = find('[data-action="brainfm-permission"]');
  permission.hidden = !brainFM.installed || brainFM.permission;
  permission.disabled = !state.ready || !state.brainFMEnabled;
  const open = find('[data-action="brainfm-open"]');
  open.hidden = !brainFM.installed || !brainFM.permission;
  open.disabled = !state.ready || !state.brainFMEnabled;
  find('[data-focus-locked]').hidden = !state.focusLocked;
}

function render() {
  renderMusic();
  renderFocus();
  const error = localError || state.error?.message;
  find('.settings-error').hidden = !error;
  text('[data-error-message]', error || '');
  const status = !state.ready ? 'loading' : error ? 'error' : requested ? 'pending' : 'saved';
  find('.save-state').dataset.state = status;
  text('[data-save-state]', { loading: 'Loading…', error: 'Not saved', pending: 'Saving…', saved: state.saved ? 'Saved' : 'Ready' }[status]);
  root.dataset.ready = String(state.ready);
}

function receiveSnapshot(value) {
  const snapshot = settingsSnapshot(value);
  if (!snapshot) return;
  state = snapshot;
  if (requested && (state.error || Object.entries(requested).every(([key, value]) => state[key] === value))) {
    clearTimeout(requestTimer);
    if (Object.hasOwn(requested, 'focusMinutes')) durationDirty = false;
    requested = null;
    localError = null;
  }
  if (keyboardUpdate || reduced()) instant(render); else render();
  if (!requested) {
    if (pendingFocus && (document.activeElement === document.body || document.activeElement.disabled)) find(pendingFocus)?.focus({ preventScroll: true });
    keyboardUpdate = false;
    pendingFocus = null;
  }
}

function commitDuration({ keyboard = false } = {}) {
  const input = find('#default-minutes');
  const minutes = durationValue(input.value);
  const error = minutes === null ? 'Choose a whole number from 1 to 180.' : '';
  input.setAttribute('aria-invalid', String(Boolean(error)));
  find('#duration-error').hidden = !error;
  text('#duration-error', error);
  if (error) { input.focus(); return; }
  if (minutes === state.focusMinutes) { durationDirty = false; render(); return; }
  sendChanges({ focusMinutes: minutes }, { keyboard });
}

all('[data-section]').forEach((button, index) => {
  button.addEventListener('click', event => setSection(button.dataset.section, { animate: event.detail > 0 }));
  button.addEventListener('keydown', event => {
    const next = { ArrowDown: index + 1, ArrowRight: index + 1, ArrowUp: index - 1, ArrowLeft: index - 1, Home: 0, End: SETTINGS_SECTIONS.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    setSection(SETTINGS_SECTIONS[(next + SETTINGS_SECTIONS.length) % SETTINGS_SECTIONS.length], { focus: true, animate: false });
  });
});

function radioGroup(selector, key, datasetKey) {
  const buttons = all(selector);
  buttons.forEach((button, index) => {
    button.addEventListener('click', event => sendChanges({ [key]: button.dataset[datasetKey] }, { keyboard: event.detail === 0 }));
    button.addEventListener('keydown', event => {
      const next = { ArrowRight: index + 1, ArrowDown: index + 1, ArrowLeft: index - 1, ArrowUp: index - 1, Home: 0, End: buttons.length - 1 }[event.key];
      if (next === undefined) return;
      event.preventDefault();
      const target = buttons[(next + buttons.length) % buttons.length];
      if (target.disabled) return;
      target.focus({ preventScroll: true });
      sendChanges({ [key]: target.dataset[datasetKey] }, { keyboard: true });
    });
  });
}
radioGroup('[data-source]', 'musicSource', 'source');
radioGroup('[data-activity]', 'focusActivity', 'activity');
all('[data-minutes]').forEach(button => button.addEventListener('click', event => {
  durationDirty = false;
  find('#default-minutes').setAttribute('aria-invalid', 'false');
  find('#duration-error').hidden = true;
  sendChanges({ focusMinutes: Number(button.dataset.minutes) }, { keyboard: event.detail === 0 });
}));
find('#default-minutes').addEventListener('input', () => {
  durationDirty = true;
  find('.duration-apply').hidden = false;
  find('#default-minutes').setAttribute('aria-invalid', 'false');
  find('#duration-error').hidden = true;
});
find('#default-minutes').addEventListener('change', () => { if (durationDirty) commitDuration(); });
find('#duration-form').addEventListener('submit', event => { event.preventDefault(); commitDuration({ keyboard: true }); });
find('#default-minutes').addEventListener('keydown', event => {
  if (event.key !== 'Escape') return;
  event.preventDefault(); event.stopPropagation();
  durationDirty = false;
  find('#duration-error').hidden = true;
  find('#default-minutes').setAttribute('aria-invalid', 'false');
  render();
});
find('#brainfm-toggle').addEventListener('click', event => sendChanges({ brainFMEnabled: !state.brainFMEnabled }, { keyboard: event.detail === 0 }));
const actions = { 'music-connect': 'musicConnect', 'music-open': 'musicOpen', 'brainfm-permission': 'brainfmSettings', 'brainfm-open': 'brainfm' };
all('[data-action]').forEach(button => button.addEventListener('click', () => native({ action: actions[button.dataset.action] })));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.preventDefault(); native({ action: 'settingsClose' }); }
});
media.addEventListener('change', () => { if (reduced()) document.getAnimations().forEach(animation => animation.cancel()); });

window.LiltSettings = Object.freeze({
  receiveSnapshot,
  configure({ reducedMotion } = {}) {
    if (typeof reducedMotion === 'boolean') root.classList.toggle('reduce-motion', reducedMotion);
    if (reduced()) document.getAnimations().forEach(animation => animation.cancel());
  },
  setSection,
  inspect: () => structuredClone({ ...state, section, requested, localError, reducedMotion: reduced(), errors }),
});
instant(render);
await document.fonts.ready;
native({ action: 'settingsReady' });
