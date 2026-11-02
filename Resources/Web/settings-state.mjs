export const MUSIC_SOURCES = Object.freeze({ spotify: 'Spotify', appleMusic: 'Apple Music', meld: 'Meld' });
export const SETTINGS_SECTIONS = ['music', 'focus', 'shelf', 'general'];
export const freshSettings = () => ({ musicSource: 'spotify', brainFMEnabled: false, notificationBannersEnabled: false, notificationCaptureStatus: 'disabled', notificationCaptureMessage: 'Off. No notifications are read.', focusMinutes: 25, focusActivity: 'deepWork', shelfShortDays: 7, shelfLongDays: 30, displayID: '', displays: [], focusSound: true, focusNotificationsEnabled: false, focusNotificationStatus: 'off', shortcutEnabled: true, openAtLogin: false, shortcutLabel: '⌃⌥L', shortcutConflict: false, displayUnavailable: false, musicBusy: false, focusLocked: false, providers: [], brainFM: { installed: false, permission: false }, error: null, saved: false, ready: false });

export function settingsSnapshot(value) {
  if (!value || !Object.hasOwn(MUSIC_SOURCES, value.musicSource)
    || !['deepWork', 'lightWork'].includes(value.focusActivity)
    || !Number.isInteger(value.focusMinutes) || value.focusMinutes < 1 || value.focusMinutes > 180
    || !['shelfShortDays', 'shelfLongDays'].every(key => Number.isInteger(value[key]) && value[key] >= 1 && value[key] <= 3650)
    || !['brainFMEnabled', 'focusSound', 'shortcutEnabled', 'openAtLogin', 'shortcutConflict', 'musicBusy', 'focusLocked', 'saved'].every(key => typeof value[key] === 'boolean')
    || typeof value.shortcutLabel !== 'string'
    || !Array.isArray(value.providers)
    || typeof value.displayID !== 'string' || !Array.isArray(value.displays) || typeof value.displayUnavailable !== 'boolean'
    || typeof value.brainFM?.installed !== 'boolean' || typeof value.brainFM?.permission !== 'boolean'
    || (value.error !== null && (typeof value.error?.code !== 'string' || typeof value.error?.message !== 'string'))) return null;
  if (value.notificationBannersEnabled !== undefined && typeof value.notificationBannersEnabled !== 'boolean') return null;
  if (value.notificationCaptureStatus !== undefined && !['disabled', 'diagnostic', 'suspended', 'permission', 'unsupported'].includes(value.notificationCaptureStatus)) return null;
  if (value.notificationCaptureMessage !== undefined && typeof value.notificationCaptureMessage !== 'string') return null;
  if (value.focusNotificationsEnabled !== undefined && typeof value.focusNotificationsEnabled !== 'boolean') return null;
  if (value.focusNotificationStatus !== undefined && !['off', 'allowed', 'permission', 'denied', 'error', 'diagnostic'].includes(value.focusNotificationStatus)) return null;
  if (value.focusNotificationRequesting !== undefined && typeof value.focusNotificationRequesting !== 'boolean') return null;
  if (value.shortcut !== undefined && (!Number.isInteger(value.shortcut?.keyCode) || value.shortcut.keyCode < 0 || value.shortcut.keyCode > 127
    || !Number.isInteger(value.shortcut?.modifiers) || value.shortcut.modifiers < 0 || value.shortcut.modifiers > 0xffffffff
    || (value.shortcut.modifiers & ~6912) !== 0 || (value.shortcut.modifiers & 6400) === 0)) return null;
  const providers = value.providers.filter(provider => provider && Object.hasOwn(MUSIC_SOURCES, provider.id)
    && typeof provider.installed === 'boolean' && typeof provider.running === 'boolean'
    && typeof provider.availability === 'string');
  const displays = value.displays.filter(display => display && typeof display.id === 'string' && typeof display.name === 'string');
  return { ...freshSettings(), ...value, providers, displays, ready: true };
}

// Optimistic display: show a requested value until native confirms; clearing the request rolls it back.
export const shownValue = (state, requested, key) => requested && Object.hasOwn(requested, key) ? requested[key] : state[key];

const RETENTION_PRESETS = { shelfShortDays: [1, 3, 7, 14, 30], shelfLongDays: [7, 30, 90, 180, 365] };
export const daysLabel = days => days === 1 ? '1 day' : `${days} days`;

// Menu choices for a setting; a stored value outside the presets stays listed so it is never hidden.
export function menuOptions(key, state) {
  if (key === 'displayID') {
    const options = [{ value: '', label: 'Automatic' }, ...state.displays.map(item => ({ value: item.id, label: item.name }))];
    if (state.displayID && !options.some(option => option.value === state.displayID)) options.push({ value: state.displayID, label: 'Disconnected display' });
    return options;
  }
  return [...new Set([...RETENTION_PRESETS[key], state[key]])].sort((a, b) => a - b).map(days => ({ value: days, label: daysLabel(days) }));
}

export function providerState(provider) {
  if (!provider) return { status: 'checking', label: 'Checking connection…', connect: false, open: false };
  if (!provider.installed) return { status: 'missing', label: 'Not installed', connect: false, open: false };
  if (!provider.running) return { status: 'offline', label: 'Not running', connect: false, open: true };
  const states = {
    ready: { status: 'ready', label: 'Connected', connect: false, open: true },
    empty: { status: 'ready', label: 'Connected · no track selected', connect: false, open: true },
    checking: { status: 'checking', label: 'Checking connection…', connect: true, open: true },
    disabled: { status: 'disabled', label: 'Connection disabled in this test', connect: false, open: false },
    permission: { status: 'permission', label: 'Permission needed', connect: true, open: true },
    unavailable: { status: 'unavailable', label: 'Not connected', connect: true, open: true },
    offline: { status: 'offline', label: 'Not connected', connect: true, open: true },
  };
  return states[provider.availability] || { status: 'unavailable', label: 'Connection unavailable', connect: true, open: true };
}

export function durationValue(raw) {
  const value = Number(raw);
  return String(raw).trim() && Number.isInteger(value) && value >= 1 && value <= 180 ? value : null;
}

export function retentionValue(raw) {
  const value = Number(raw);
  return String(raw).trim() && Number.isInteger(value) && value >= 1 && value <= 3650 ? value : null;
}
