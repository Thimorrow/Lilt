export const MUSIC_SOURCES = Object.freeze({ spotify: 'Spotify', appleMusic: 'Apple Music', meld: 'Meld' });
export const SETTINGS_SECTIONS = ['music', 'focus'];
export const freshSettings = () => ({ musicSource: 'spotify', brainFMEnabled: false, focusMinutes: 25, focusActivity: 'deepWork', musicBusy: false, focusLocked: false, providers: [], brainFM: { installed: false, permission: false }, error: null, saved: false, ready: false });

export function settingsSnapshot(value) {
  if (!value || !Object.hasOwn(MUSIC_SOURCES, value.musicSource)
    || !['deepWork', 'lightWork'].includes(value.focusActivity)
    || !Number.isInteger(value.focusMinutes) || value.focusMinutes < 1 || value.focusMinutes > 180
    || !['brainFMEnabled', 'musicBusy', 'focusLocked', 'saved'].every(key => typeof value[key] === 'boolean')
    || !Array.isArray(value.providers)
    || typeof value.brainFM?.installed !== 'boolean' || typeof value.brainFM?.permission !== 'boolean'
    || (value.error !== null && (typeof value.error?.code !== 'string' || typeof value.error?.message !== 'string'))) return null;
  const providers = value.providers.filter(provider => provider && Object.hasOwn(MUSIC_SOURCES, provider.id)
    && typeof provider.installed === 'boolean' && typeof provider.running === 'boolean'
    && typeof provider.availability === 'string');
  return { ...freshSettings(), ...value, providers, ready: true };
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
