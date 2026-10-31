import { VIEWS, clock, elapsedAt, freshMusic, musicSnapshot, musicAction } from './model.mjs';
import { freshFocus, focusSnapshot, focusLocked, focusAction } from './focus-state.mjs';

const root = document.documentElement;
const notch = document.querySelector('#notch');
const compact = document.querySelector('.notch-compact');
const panel = document.querySelector('.notch-panel');
const tabs = [...document.querySelectorAll('[role="tab"]')];
const viewPanels = VIEWS.map(view => document.querySelector(`#view-${view}`));
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const errors = [];
const state = {
  view: 'music', open: false,
  music: freshMusic(),
  focus: freshFocus(),
  settings: { musicSource: 'meld', sourceName: 'Meld', brainFMEnabled: true },
  shelf: [], shelfMessage: null,
};
const focusMenu = { kind: null, custom: false };
const menuAnimations = new WeakMap();
const reduced = () => reducedMotion.matches || root.classList.contains('reduce-motion');
const native = message => window.webkit?.messageHandlers?.lilt?.postMessage(message);
const each = (name, apply) => document.querySelectorAll(`[data-live="${name}"]`).forEach(apply);
const text = (name, value) => each(name, element => { if (element.textContent !== value) element.textContent = value; });
const icon = (name, value) => each(name, element => element.setAttribute('href', value));
const elapsed = () => elapsedAt(state.music, performance.now());
const remaining = () => state.focus.remaining;
const sourceName = () => state.music.sourceName || state.settings.sourceName;
const brainFMEnabled = () => state.focus.brainFMEnabled ?? state.settings.brainFMEnabled;
function announce(message) { document.querySelector('[data-announce]').textContent = message; }
window.addEventListener('error', event => errors.push(event.message));
window.addEventListener('unhandledrejection', event => errors.push(String(event.reason)));

function renderWings() {
  const { music, shelf } = state;
  const view = state.view;
  for (const wing of notch.querySelectorAll('[data-wing], [data-compact]')) {
    const side = wing.dataset.wing || wing.dataset.compact;
    const key = `${side}-${view}-${music.id}-${music.cover}-${music.playing}-${music.availability}-${state.focus.phase}-${Boolean(state.focus.error)}-${shelf.length}`;
    if (side === 'left') {
      if (wing.dataset.key === key) continue;
      wing.innerHTML = view === 'music'
        ? `<span class="mini-cover">${music.cover ? '<img alt="" data-music-cover>' : '<svg viewBox="0 0 24 24" aria-hidden="true"><use href="#i-music"/></svg>'}</span>`
        : view === 'focus' ? `<span class="dot ${state.focus.error ? 'is-error' : state.focus.phase === 'completed' ? 'is-complete' : ''}"></span>` : '<svg class="glyph" aria-hidden="true"><use href="#i-shelf"/></svg>';
      const image = wing.querySelector('[data-music-cover]');
      if (image) image.src = music.cover;
    } else if (view === 'music' && music.playing) {
      if (wing.dataset.key === key) continue;
      wing.innerHTML = '<span class="wave"><i></i><i></i><i></i><i></i><i></i></span>';
    } else {
      wing.textContent = view === 'music' ? music.availability === 'ready' ? clock(elapsed()) : sourceName() : view === 'focus' ? state.focus.error ? '!' : state.focus.phase === 'completed' ? 'Done' : clock(remaining()) : shelf.length ? String(shelf.length) : '';
    }
    wing.dataset.key = key;
  }
  text('compact-label', `Open the notch: ${view}, ${view === 'music' ? music.title || sourceName() : view === 'focus' ? clock(remaining()) : `${shelf.length} files`}`);
}

function render() {
  const music = state.music;
  const connected = music.availability === 'ready';
  const running = state.focus.phase === 'running';
  const left = remaining();
  const provider = sourceName();
  text('title', connected ? music.title : provider);
  const emptyNote = { checking: 'Connecting…', offline: 'Not running', empty: `Choose a song in ${provider}`, unavailable: 'Connection unavailable', disabled: 'Player disabled in this test' }[music.availability];
  text('artist', connected ? [music.artist, provider].filter(Boolean).join(' · ') : emptyNote || provider);
  text('elapsed', clock(elapsed()));
  text('duration', music.duration > 0 ? clock(music.duration) : '–:––');
  each('bar', element => element.style.setProperty('--p', music.duration > 0 ? elapsed() / music.duration : 0));
  const artwork = document.querySelector('.cover img');
  if (music.cover) { if (artwork.getAttribute('src') !== music.cover) artwork.src = music.cover; }
  else artwork.removeAttribute('src');
  artwork.hidden = !music.cover;
  document.querySelector('.cover svg').toggleAttribute('hidden', Boolean(music.cover));
  const note = music.error?.message || (music.buffering ? `Loading ${provider}…` : music.pending ? `Waiting for ${provider}…` : '');
  text('music-note', note);
  const musicNote = document.querySelector('.music-note');
  musicNote.hidden = !note && connected;
  musicNote.title = note;
  const progress = document.querySelector('.progress');
  progress.setAttribute('aria-label', `${provider} playback position`);
  progress.hidden = !connected || Boolean(note);
  progress.setAttribute('aria-valuetext', `${clock(elapsed())}${music.duration > 0 ? ` of ${clock(music.duration)}` : ', duration unknown'}`);
  if (music.duration > 0) { progress.setAttribute('aria-valuenow', elapsed()); progress.setAttribute('aria-valuemax', music.duration); }
  else { progress.removeAttribute('aria-valuenow'); progress.removeAttribute('aria-valuemax'); }
  document.querySelector('[data-action="meld-open"]').hidden = connected && !music.error;
  document.querySelector('[data-action="meld-open"]').textContent = `Open ${provider}`;
  document.querySelector('.track-meta').title = connected ? [music.title, music.artist, music.album].filter(Boolean).join(' · ') : emptyNote || provider;
  icon('play-icon', state.music.playing ? '#i-pause' : '#i-play');
  icon('focus-icon', running ? '#i-pause' : '#i-play');
  text('focus', clock(left));
  const pending = state.focus.pending;
  const error = state.focus.error;
  const withMusic = brainFMEnabled();
  const focusNote = state.focus.restoring ? withMusic ? 'Checking Brain.fm…' : 'Restoring timer…' : pending ? withMusic ? pending.action === 'start' ? 'Starting Brain.fm…' : 'Pausing Brain.fm…' : 'Updating timer…' : error ? error.code === 'permission' ? 'Allow Lilt in Accessibility.' : error.message : '';
  text('focus-note', focusNote);
  document.querySelector('.focus-note').hidden = !focusNote;
  document.querySelector('.focus-note').title = error?.message || '';
  document.querySelector('.focus-note').classList.toggle('has-error', Boolean(error));
  document.querySelector('[data-action="brainfm-settings"]').hidden = !withMusic || error?.code !== 'permission';
  document.querySelector('[data-action="brainfm-open"]').hidden = !withMusic || !error || error.code === 'permission';
  const minutes = state.focus.duration / 60;
  const durationLabel = `${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`;
  text('focus-activity', state.focus.activity === 'lightWork' ? 'Light Work' : 'Deep Work');
  document.querySelector('#focus-duration').setAttribute('aria-label', `Focus duration, ${durationLabel}. ${clock(left)} remaining.`);
  document.querySelector('#focus-activity').setAttribute('aria-label', `Focus activity, ${state.focus.activity === 'lightWork' ? 'Light Work' : 'Deep Work'}`);
  document.querySelector('#focus-activity-menu').setAttribute('aria-label', 'Focus activity');
  renderFocusMenu();
  const play = document.querySelector('[data-action="play"]');
  play.disabled = Boolean(music.pending) || music.buffering || !connected || !(music.playing ? music.canPause : music.canPlay);
  play.setAttribute('aria-busy', String(Boolean(music.pending) || music.buffering));
  play.setAttribute('aria-label', music.pending ? `Waiting for ${provider}` : music.playing ? `Pause ${provider}` : `Play ${provider}`);
  play.title = music.playing ? `Pause ${provider}` : `Play ${provider}`;
  document.querySelector('[data-action="prev"]').setAttribute('aria-label', `Previous ${provider} track`);
  document.querySelector('[data-action="next"]').setAttribute('aria-label', `Next ${provider} track`);
  document.querySelector('[data-action="prev"]').disabled = Boolean(music.pending) || !connected || !music.canPrevious;
  document.querySelector('[data-action="next"]').disabled = Boolean(music.pending) || !connected || !music.canNext;
  play.setAttribute('aria-pressed', String(state.music.playing));
  const focus = document.querySelector('[data-action="focus"]');
  focus.disabled = Boolean(pending) || !state.focus.ready || state.focus.restoring;
  focus.setAttribute('aria-busy', String(Boolean(pending)));
  focus.setAttribute('aria-label', pending ? withMusic ? 'Waiting for Brain.fm' : 'Updating focus timer' : error ? withMusic ? 'Retry Brain.fm control' : 'Retry focus timer' : running ? withMusic ? 'Pause focus and Brain.fm' : 'Pause focus timer' : withMusic ? 'Start focus and Brain.fm' : 'Start focus timer');
  focus.title = pending ? withMusic ? 'Waiting for Brain.fm' : 'Updating timer' : running ? withMusic ? 'Pause timer and Brain.fm' : 'Pause timer' : withMusic ? 'Start Brain.fm in the background' : 'Start timer';
  document.querySelector('[data-action="focus-reset"]').disabled = Boolean(pending) || !state.focus.ready || state.focus.restoring;
  document.querySelector('[data-action="focus-reset"]').setAttribute('aria-label', `Reset the focus timer to ${durationLabel}`);
  root.classList.toggle('music-playing', state.music.playing);
  root.classList.toggle('focus-running', running);
  renderWings();
}

function renderShelf() {
  const list = document.querySelector('[data-live="files"]');
  const scroll = list.scrollLeft;
  const focused = document.activeElement?.dataset.fileID;
  const items = state.shelf.map(file => {
    const item = document.createElement('li');
    item.classList.toggle('is-missing', !file.available);
    const main = document.createElement('button');
    main.type = 'button';
    main.className = 'file-main';
    main.draggable = file.available;
    main.dataset.fileID = file.id;
    main.setAttribute('aria-label', `${file.available ? 'Preview' : 'Unavailable file'}: ${file.name}, ${file.location}`);
    main.title = `${file.name} · ${file.location}${file.available ? '' : ' · File unavailable'}`;
    main.innerHTML = '<svg aria-hidden="true"><use href="#i-file"/></svg><span><strong></strong><small></small></span>';
    main.querySelector('strong').textContent = file.name;
    main.querySelector('small').textContent = file.available ? file.location : 'File unavailable';
    main.addEventListener('click', () => shelfCommand('preview', file.id));
    main.addEventListener('dblclick', () => shelfCommand('open', file.id));
    main.addEventListener('dragstart', event => {
      event.preventDefault();
      const rect = main.getBoundingClientRect();
      shelfCommand('drag', file.id, { x: rect.x, y: rect.y, width: rect.width, height: rect.height });
    });
    main.addEventListener('keydown', event => {
      if (event.key === ' ' || event.key === 'Enter') { event.preventDefault(); shelfCommand('preview', file.id); }
      if (event.key === 'Backspace' || event.key === 'Delete') { event.preventDefault(); shelfCommand('remove', file.id); }
    });
    const menu = document.createElement('button');
    menu.type = 'button';
    menu.className = 'file-menu';
    menu.textContent = '⋯';
    menu.setAttribute('aria-label', `Actions for ${file.name}`);
    const openMenu = event => {
      event.preventDefault();
      const rect = menu.getBoundingClientRect();
      shelfCommand('menu', file.id, { x: rect.x, y: rect.bottom });
    };
    menu.addEventListener('click', openMenu);
    item.addEventListener('contextmenu', openMenu);
    item.append(main, menu);
    return item;
  });
  list.replaceChildren(...items);
  list.scrollLeft = scroll;
  list.hidden = !items.length;
  document.querySelector('.drop').hidden = Boolean(items.length);
  document.querySelector('.shelf-actions').hidden = !items.length;
  document.querySelector('[data-live="shelf-note"]').textContent = state.shelfMessage || '';
  document.querySelector('.shelf-note').hidden = !state.shelfMessage;
  if (focused) [...list.querySelectorAll('.file-main')].find(element => element.dataset.fileID === focused)?.focus();
  render();
}

function shelfCommand(command, id, extra = {}) {
  native({ action: 'shelfAction', command, id, ...extra });
}

function receiveShelfSnapshot(value) {
  if (!value || !Array.isArray(value.items)) return;
  state.shelf = value.items.filter(file => file && typeof file.id === 'string' && typeof file.name === 'string' && typeof file.location === 'string' && typeof file.available === 'boolean');
  state.shelfMessage = typeof value.message === 'string' ? value.message : null;
  renderShelf();
}

function setView(view, { focus = false, animate = true } = {}) {
  if (!VIEWS.includes(view)) return;
  closeFocusMenu({ animate: false });
  const index = VIEWS.indexOf(view);
  const instant = !animate || reduced() || !state.open;
  notch.classList.toggle('instant-view', instant);
  state.view = view;
  if (view === 'shelf') shelfCommand('refresh');
  notch.dataset.view = view;
  notch.style.setProperty('--tab-index', index);
  for (const tab of tabs) {
    const selected = tab.dataset.view === view;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    if (selected && focus) tab.focus({ preventScroll: true });
  }
  viewPanels.forEach((viewPanel, panelIndex) => {
    const selected = panelIndex === index;
    viewPanel.hidden = false;
    viewPanel.inert = !selected;
    viewPanel.setAttribute('aria-hidden', String(!selected));
    viewPanel.dataset.position = selected ? 'active' : 'inactive';
  });
  if (instant) {
    void panel.offsetWidth;
    notch.classList.remove('instant-view');
  }
  render();
}

function setOpen(open, { focus = false } = {}) {
  if (!open) closeFocusMenu({ animate: false });
  if (state.open === open) return;
  state.open = Boolean(open);
  notch.dataset.state = open ? 'open' : 'compact';
  compact.setAttribute('aria-expanded', String(open));
  panel.inert = !open;
  compact.inert = open;
  if (focus) (open ? tabs.find(tab => tab.dataset.view === state.view) : compact).focus({ preventScroll: true });
  native({ action: 'openChanged', open: state.open });
}

let tick;
function schedule() {
  clearTimeout(tick);
  if (!state.music.playing) return;
  tick = setTimeout(() => {
    render();
    schedule();
  }, 250);
}

function receiveMusicSnapshot(value) {
  const snapshot = musicSnapshot(value, performance.now());
  if (!snapshot) return;
  const before = state.music;
  if (JSON.stringify({ ...before, since: 0 }) === JSON.stringify({ ...snapshot, since: 0 })) return;
  state.music = snapshot;
  render(); schedule();
  if (before.id && snapshot.id && before.id !== snapshot.id && !reduced()) {
    const cover = document.querySelector('.cover');
    cover.getAnimations().forEach(animation => animation.cancel());
    cover.animate([{ transform: 'translateX(10px) scale(.9)', opacity: 0.4 }, { transform: 'none', opacity: 1 }], { duration: 320, easing: 'cubic-bezier(.16,1,.3,1)' });
  }
  if (snapshot.error && snapshot.error.message !== before.error?.message) announce(snapshot.error.message);
}

function controlMusic(command) {
  const music = state.music;
  if (music.pending || music.availability !== 'ready') return;
  const allowed = { play: music.canPlay, pause: music.canPause, next: music.canNext, previous: music.canPrevious };
  if (allowed[command]) native({ action: 'musicAction', command });
}

function receiveFocusSnapshot(value) {
  const snapshot = focusSnapshot(value);
  if (!snapshot) return;
  const before = state.focus;
  state.focus = snapshot;
  render();
  if (snapshot.error && snapshot.error.message !== before.error?.message) announce(snapshot.error.message);
  else if (snapshot.phase === 'completed' && before.phase !== 'completed') announce(brainFMEnabled() ? 'Focus session complete. Brain.fm paused.' : 'Focus session complete.');
}

function receiveSettingsSnapshot(value) {
  if (!value || !['spotify', 'appleMusic', 'meld'].includes(value.musicSource) || typeof value.brainFMEnabled !== 'boolean') return;
  const names = { spotify: 'Spotify', appleMusic: 'Apple Music', meld: 'Meld' };
  state.settings = { musicSource: value.musicSource, sourceName: names[value.musicSource], brainFMEnabled: value.brainFMEnabled };
  render();
}

function controlFocus(command) {
  if (state.focus.pending || state.focus.restoring || !state.focus.ready) return;
  native({ action: 'focusAction', command });
}

function configureFocus({ activity = state.focus.activity, minutes = state.focus.duration / 60 } = {}, { animate = false } = {}) {
  if (focusLocked(state.focus)) return false;
  const custom = document.querySelector('#focus-minutes');
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 180) { custom.setCustomValidity('Choose 1–180 minutes.'); custom.reportValidity(); return false; }
  custom.setCustomValidity('');
  if (activity !== state.focus.activity || minutes !== state.focus.duration / 60) native({ action: 'focusConfigure', activity, minutes });
  closeFocusMenu({ restoreFocus: true, animate });
  return true;
}

function animateFocusMenu(menu, open, animate) {
  const previous = menuAnimations.get(menu);
  const style = getComputedStyle(menu);
  const from = menu.hidden ? { opacity: 0, transform: 'scale(.95)' } : { opacity: style.opacity, transform: style.transform };
  previous?.cancel();
  menuAnimations.delete(menu);
  menu.hidden = false;
  menu.inert = !open;
  menu.setAttribute('aria-hidden', String(!open));
  menu.dataset.menuState = open ? 'open' : 'closed';
  const to = { opacity: open ? 1 : 0, transform: open ? 'scale(1)' : 'scale(.95)' };
  Object.assign(menu.style, to);
  const finish = () => {
    if (menu.dataset.menuState === 'closed') menu.hidden = true;
    if (!focusMenu.kind && [...document.querySelectorAll('.focus-menu')].every(item => item.hidden)) delete document.querySelector('#view-focus').dataset.menuOpen;
  };
  if (!animate || reduced()) { finish(); return; }
  const animation = menu.animate([from, to], { duration: open ? 200 : 150, easing: open ? 'cubic-bezier(.23,1,.32,1)' : 'ease-in' });
  menuAnimations.set(menu, animation);
  const complete = () => {
    if (menuAnimations.get(menu) !== animation) return;
    menuAnimations.delete(menu);
    finish();
  };
  animation.finished.then(complete, complete);
}

function closeFocusMenu({ restoreFocus = false, animate = true } = {}) {
  const kind = focusMenu.kind;
  if (!kind) {
    if (!animate) for (const menu of document.querySelectorAll('.focus-menu')) {
      if (!menu.hidden) animateFocusMenu(menu, false, false);
    }
    return;
  }
  focusMenu.kind = null;
  delete document.querySelector('#view-focus').dataset.menuOpen;
  const menu = document.querySelector(`#focus-${kind}-menu`);
  animateFocusMenu(menu, false, animate);
  document.querySelectorAll('.focus-trigger').forEach(trigger => trigger.setAttribute('aria-expanded', 'false'));
  if (restoreFocus && state.open && state.view === 'focus') {
    const trigger = document.querySelector(`#focus-${kind}`);
    (focusLocked(state.focus) ? document.querySelector('#tab-focus') : trigger).focus({ preventScroll: true });
  }
}

function renderFocusMenu() {
  const locked = focusLocked(state.focus);
  if (locked && focusMenu.kind) closeFocusMenu({ restoreFocus: true });
  document.querySelectorAll('.focus-trigger').forEach(trigger => { trigger.disabled = locked; });
  const minutes = state.focus.duration / 60;
  for (const option of document.querySelectorAll('#focus-activity-menu [data-activity]')) option.setAttribute('aria-checked', String(option.dataset.activity === state.focus.activity));
  for (const option of document.querySelectorAll('#focus-duration-menu [data-minutes]')) option.setAttribute('aria-checked', String(option.dataset.minutes === ([25, 50].includes(minutes) ? String(minutes) : 'custom')));
  if (focusMenu.kind === 'duration') {
    document.querySelector('#focus-config').hidden = !focusMenu.custom;
    document.querySelector('[data-action="focus-custom"]').hidden = focusMenu.custom;
  }
  const input = document.querySelector('#focus-minutes');
  if (!focusMenu.custom) input.value = minutes;
  input.disabled = locked;
  if (!focusMenu.kind) return;
  document.querySelector('#view-focus').dataset.menuOpen = focusMenu.kind;
  const menu = document.querySelector(`#focus-${focusMenu.kind}-menu`);
  const trigger = document.querySelector(`#focus-${focusMenu.kind}`);
  const view = document.querySelector('#view-focus').getBoundingClientRect();
  const anchor = trigger.getBoundingClientRect();
  const left = Math.max(0, Math.min(anchor.left - view.left, view.width - menu.offsetWidth));
  const top = Math.max(0, Math.min(anchor.bottom - view.top + 4, view.height - menu.offsetHeight));
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;
  menu.style.transformOrigin = `${anchor.left + anchor.width / 2 - view.left - left}px ${anchor.bottom - view.top - top}px`;
}

function openFocusMenu(kind, { last = false, animate = false } = {}) {
  if (focusLocked(state.focus)) return;
  if (focusMenu.kind === kind) { closeFocusMenu({ restoreFocus: true, animate }); return; }
  if (focusMenu.kind) closeFocusMenu({ animate: false });
  focusMenu.kind = kind;
  focusMenu.custom = false;
  const input = document.querySelector('#focus-minutes');
  input.value = state.focus.duration / 60;
  input.setCustomValidity('');
  const menu = document.querySelector(`#focus-${kind}-menu`);
  const wasHidden = menu.hidden;
  menu.hidden = false;
  if (wasHidden) { menu.style.opacity = '0'; menu.style.transform = 'scale(.95)'; }
  document.querySelector(`#focus-${kind}`).setAttribute('aria-expanded', 'true');
  renderFocusMenu();
  animateFocusMenu(menu, true, animate);
  const options = [...menu.querySelectorAll('[role="menuitemradio"]')];
  (last ? options.at(-1) : options.find(option => option.getAttribute('aria-checked') === 'true') || options[0]).focus({ preventScroll: true });
}

const actions = {
  'focus-menu'(event) { openFocusMenu(event.target.closest('[data-menu]').dataset.menu, { animate: event.detail > 0 }); },
  'focus-activity'(event) {
    configureFocus({ activity: event.target.closest('[data-activity]').dataset.activity }, { animate: event.detail > 0 });
  },
  'focus-duration'(event) {
    configureFocus({ minutes: Number(event.target.closest('[data-minutes]').dataset.minutes) }, { animate: event.detail > 0 });
  },
  'focus-custom'() {
    focusMenu.custom = true;
    renderFocusMenu();
    const input = document.querySelector('#focus-minutes');
    input.focus(); input.select();
  },
  play: () => controlMusic(musicAction(state.music)),
  prev: () => controlMusic('previous'),
  next: () => controlMusic('next'),
  'meld-open': () => native({ action: (state.music.source || state.settings.musicSource) === 'meld' ? 'meldOpen' : 'musicOpen' }),
  settings: () => native({ action: 'settingsOpen' }),
  focus() {
    controlFocus(focusAction(state.focus));
  },
  'focus-reset': () => controlFocus('reset'),
  'brainfm-settings': () => native({ action: 'brainfmSettings' }),
  'brainfm-open': () => native({ action: 'brainfm' }),
  choose: () => native({ action: 'chooseFiles' }),
  clear: () => shelfCommand('clear'),
  fold: () => setOpen(false, { focus: true }),
};

document.addEventListener('click', event => {
  const action = event.target.closest?.('[data-action]')?.dataset.action;
  if (Object.hasOwn(actions, action)) { actions[action](event); return; }
  if (state.open && notch.contains(event.target) && !event.target.closest('button, input, select, textarea, a, label, [role="button"], [role="menu"], [role="dialog"], [contenteditable="true"], [tabindex]:not([tabindex="-1"]), [data-file-id]')) setOpen(false);
});
compact.addEventListener('click', () => setOpen(true, { focus: true }));
tabs.forEach((tab, index) => {
  tab.addEventListener('click', event => setView(tab.dataset.view, { animate: event.detail > 0 }));
  tab.addEventListener('keydown', event => {
    const next = { ArrowRight: index + 1, ArrowLeft: index - 1, Home: 0, End: tabs.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    setView(tabs[(next + tabs.length) % tabs.length].dataset.view, { focus: true, animate: false });
  });
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    if (focusMenu.kind) closeFocusMenu({ restoreFocus: true, animate: false });
    else setOpen(false, { focus: true });
  }
});
document.addEventListener('pointerdown', event => {
  if (focusMenu.kind && !event.target.closest('.focus-menu, .focus-trigger')) closeFocusMenu();
  if (!notch.contains(event.target) && state.open) setOpen(false);
});
document.querySelectorAll('.focus-trigger').forEach(trigger => trigger.addEventListener('keydown', event => {
  if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
  event.preventDefault();
  openFocusMenu(trigger.dataset.menu, { last: event.key === 'ArrowUp' });
}));
document.querySelectorAll('.focus-menu').forEach(menu => {
  menu.inert = true;
  menu.setAttribute('aria-hidden', 'true');
  menu.addEventListener('mousedown', event => {
    const control = event.target.closest('button, input');
    if (!control || control.disabled || menu.inert) return;
    if (control.tagName === 'BUTTON') event.preventDefault();
    control.focus({ preventScroll: true });
  });
  menu.addEventListener('keydown', event => {
    if (event.key === 'Tab') {
      if (focusMenu.custom) {
        const input = document.querySelector('#focus-minutes');
        const submit = document.querySelector('#focus-config button');
        if (event.target === input && !event.shiftKey) { event.preventDefault(); submit.focus(); return; }
        if (event.target === submit && event.shiftKey) { event.preventDefault(); input.focus(); return; }
      }
      closeFocusMenu({ restoreFocus: true, animate: false }); return;
    }
    if (event.target.matches('input')) return;
    const options = [...menu.querySelectorAll('[role="menuitemradio"]')].filter(option => !option.hidden);
    const current = options.indexOf(document.activeElement);
    if (['Enter', ' '].includes(event.key) && current >= 0) { event.preventDefault(); options[current].click(); return; }
    const next = { ArrowDown: current + 1, ArrowUp: current - 1, Home: 0, End: options.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    options[(next + options.length) % options.length].focus({ preventScroll: true });
  });
  menu.addEventListener('focusout', () => queueMicrotask(() => {
    if (focusMenu.kind && !menu.hidden && !menu.contains(document.activeElement) && document.activeElement !== document.querySelector(`#focus-${focusMenu.kind}`)) closeFocusMenu();
  }));
});
document.querySelector('#focus-minutes').addEventListener('input', event => { if (event.target.validationMessage) event.target.setCustomValidity(''); });
let customSubmitByPointer = false;
document.querySelector('#focus-config button').addEventListener('click', event => { customSubmitByPointer = event.detail > 0; });
document.querySelector('#focus-config').addEventListener('submit', event => {
  event.preventDefault();
  configureFocus({ minutes: Number(document.querySelector('#focus-minutes').value) }, { animate: customSubmitByPointer });
  customSubmitByPointer = false;
});

window.Lilt = Object.freeze({
  configure({ hardwareWidth, hardwareHeight, reducedMotion: reduce } = {}) {
    if (Number.isFinite(hardwareWidth)) root.style.setProperty('--hardware-width', `${Math.max(0, Math.min(300, hardwareWidth))}px`);
    if (Number.isFinite(hardwareHeight)) root.style.setProperty('--hardware-height', `${Math.max(24, Math.min(64, hardwareHeight))}px`);
    if (typeof reduce === 'boolean') root.classList.toggle('reduce-motion', reduce);
    if (reduced()) document.getAnimations().forEach(animation => animation.cancel());
  },
  setOpen,
  setView,
  receiveShelfSnapshot,
  receiveFocusSnapshot,
  receiveMusicSnapshot,
  receiveSettingsSnapshot,
  setDragging: dragging => notch.classList.toggle('dragging', Boolean(dragging)),
  inspect: () => structuredClone({ ...state, errors, elapsed: elapsed(), remaining: remaining() }),
});
panel.inert = true;
setView(state.view, { animate: false });
renderShelf();
await document.fonts.ready;
native({ action: 'ready' });
