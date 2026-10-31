import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshMusic, elapsedAt, musicSnapshot, musicAction, clock } from '../Resources/Web/model.mjs';
import { selectShelfItem } from '../Resources/Web/shelf-selection.mjs';

const ready = extra => ({ ...freshMusic(), availability: 'ready', id: 'track', title: 'A song', duration: 120, elapsed: 15, canPlay: true, canPause: true, ...extra });

test('Meld snapshots advance only confirmed playing audio and freeze when paused', () => {
  const playing = musicSnapshot(ready({ playing: true }), 1000);
  assert.equal(elapsedAt(playing, 3000), 17);
  assert.equal(elapsedAt(playing, 1_000_000), 120);
  const paused = musicSnapshot(ready(), 1000);
  assert.equal(elapsedAt(paused, 90_000), 15);
  assert.equal(musicAction(playing), 'pause');
  assert.equal(musicAction(paused), 'play');
});

test('unknown duration remains unknown and never invents a next song', () => {
  const music = musicSnapshot(ready({ duration: 0, elapsed: 75, playing: true }), 0);
  assert.equal(elapsedAt(music, 30_000), 105);
  assert.equal(music.id, 'track');
  assert.equal(clock(-5), '0:00');
  assert.equal(clock(Number.NaN), '0:00');
});

test('malformed snapshots and remote artwork are rejected safely', () => {
  assert.equal(musicSnapshot(ready({ elapsed: Number.NaN }), 0), null);
  assert.equal(musicSnapshot(ready({ playing: 'yes' }), 0), null);
  assert.equal(musicSnapshot(ready({ pending: 'delete' }), 0), null);
  assert.equal(musicSnapshot(ready({ error: { message: 'missing code' } }), 0), null);
  assert.equal(musicSnapshot(ready({ cover: 'https://example.com/cover.png' }), 0).cover, null);
  assert.equal(musicSnapshot(ready({ cover: 'data:image/jpeg;base64,aGVsbG8=' }), 0).cover, 'data:image/jpeg;base64,aGVsbG8=');
});

test('offline disables transport and buffering never advances playback time', () => {
  const offline = musicSnapshot(ready({ availability: 'offline', playing: true }), 0);
  assert.equal(offline.playing, false);
  assert.equal(offline.canPlay, false);
  assert.equal(offline.canPause, false);
  assert.equal(elapsedAt(offline, 90000), 15);
  const buffering = musicSnapshot(ready({ buffering: true, playing: true }), 0);
  assert.equal(buffering.playing, false);
  assert.equal(elapsedAt(buffering, 90000), 15);
  assert.equal(musicSnapshot(ready({ pending: 'play' }), 0).pending, 'play');
});

test('Shelf selection supports single, command and contiguous shift selections', () => {
  const ids = ['a', 'b', 'c', 'd'];
  let choice = selectShelfItem(ids, new Set(), null, 'b');
  assert.deepEqual([...choice.selected], ['b']);
  choice = selectShelfItem(ids, choice.selected, choice.anchor, 'd', { toggle: true });
  assert.deepEqual([...choice.selected], ['b', 'd']);
  choice = selectShelfItem(ids, choice.selected, choice.anchor, 'b', { range: true });
  assert.deepEqual([...choice.selected], ['b', 'c', 'd']);
  choice = selectShelfItem(ids, choice.selected, choice.anchor, 'c', { toggle: true });
  assert.deepEqual([...choice.selected], ['b', 'd']);
  choice = selectShelfItem(ids, choice.selected, choice.anchor, 'missing');
  assert.deepEqual([...choice.selected], ['b', 'd']);
});
