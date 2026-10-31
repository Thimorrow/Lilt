export const VIEWS = ['music', 'focus', 'shelf'];
export const clock = seconds => {
  const value = Number.isFinite(seconds) ? Math.max(0, seconds) : 0;
  return `${Math.floor(value / 60)}:${String(Math.floor(value % 60)).padStart(2, '0')}`;
};
export const freshMusic = () => ({
  availability: 'checking', id: '', title: '', artist: '', album: '', queueID: '',
  duration: 0, elapsed: 0, playing: false, buffering: false, speed: 1, cover: null,
  canPlay: false, canPause: false, canNext: false, canPrevious: false,
  pending: null, error: null, since: 0,
});
export function musicSnapshot(value, now) {
  if (!value || !['checking', 'ready', 'offline', 'empty', 'unavailable', 'disabled'].includes(value.availability)) return null;
  const result = { ...freshMusic(), ...value, since: now };
  if (!['id', 'title', 'artist', 'album', 'queueID'].every(key => typeof result[key] === 'string')) return null;
  if (!['duration', 'elapsed', 'speed'].every(key => Number.isFinite(result[key]) && result[key] >= 0)) return null;
  if (!['playing', 'buffering', 'canPlay', 'canPause', 'canNext', 'canPrevious'].every(key => typeof result[key] === 'boolean')) return null;
  if (result.pending !== null && !['play', 'pause', 'next', 'previous'].includes(result.pending)) return null;
  if (result.error !== null && (typeof result.error?.code !== 'string' || typeof result.error?.message !== 'string')) return null;
  result.cover = typeof result.cover === 'string' && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(result.cover) && result.cover.length <= 90_000 ? result.cover : null;
  if (result.availability !== 'ready') {
    result.playing = false;
    result.buffering = false;
    result.canPlay = result.canPause = result.canNext = result.canPrevious = false;
  }
  if (result.buffering) result.playing = false;
  if (result.duration > 0) result.elapsed = Math.min(result.duration, result.elapsed);
  return result;
}
export const elapsedAt = (music, now) => {
  const value = music.elapsed + (music.playing ? Math.max(0, now - music.since) / 1000 * music.speed : 0);
  return music.duration > 0 ? Math.min(music.duration, value) : value;
};
export const musicAction = music => music.playing ? 'pause' : 'play';
