// Drives the settings window of an isolated diagnostic Lilt (--ui-test-dir DIR --simulate-meld --simulate-brainfm)
// through native step lists and asserts on the returned model state. Usage: node scripts/check-native-settings.mjs DIR
import { readFile, writeFile, rename } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { join, resolve } from 'node:path';

const dir = resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw new Error('Usage: node scripts/check-native-settings.mjs TEST_DIRECTORY');

async function run(steps, settingsSize) {
  const id = randomUUID();
  await writeFile(join(dir, 'command.next.json'), JSON.stringify({ id, target: 'settings', steps, settingsSize }));
  await rename(join(dir, 'command.next.json'), join(dir, 'command.json'));
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    try {
      const response = JSON.parse(await readFile(join(dir, 'response.json'), 'utf8'));
      if (response.id === id) return response;
    } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('Native app did not respond within 30 seconds.');
}

const checks = [];
const check = (name, pass, detail) => checks.push({ name, pass: Boolean(pass), ...(pass ? {} : { detail }) });
// A complete, valid native snapshot used to simulate locks the isolated app cannot produce on demand.
const snapshot = extra => ({
  musicSource: 'spotify', sourceName: 'Spotify', brainFMEnabled: false, notificationBannersEnabled: false, focusMinutes: 25,
  focusActivity: 'deepWork', shelfShortDays: 7, shelfLongDays: 30, displayID: '', displays: [], focusSound: true,
  shortcutEnabled: true, openAtLogin: false, shortcutLabel: '⌃⌥L', shortcutConflict: false, displayUnavailable: false,
  musicBusy: false, focusLocked: false, saved: true, error: null, brainFM: { installed: true, permission: false },
  providers: [{ id: 'spotify', installed: true, running: true, availability: 'ready', message: '' }], ...extra,
});
// Any accepted update makes native send its real snapshot again, replacing an injected one.
const restore = { message: { action: 'settingsUpdate', changes: { focusSound: true } } };
const settle = { wait: 350 };

let r = await run([{ call: 'configure', value: { reducedMotion: false } }, { intent: 'section', value: 'music', keyboard: true }, settle, { capture: 'settings-music' }]);
check('native settings snapshot arrives', r.result.ready && r.result.saveStatus === 'saved', r.result.saveStatus);
check('settings window is visible', r.settingsVisible, r.settingsVisible);
check('notification banners default to off', r.result.notificationBannersEnabled === false, r.result.notificationBannersEnabled);
const initialSource = r.result.musicSource;

for (const section of ['focus', 'shelf', 'notifications', 'general', 'music']) {
  r = await run([{ intent: 'section', value: section }, { wait: 400 }, { capture: `settings-${section}` }]);
  check(`section ${section} is selected`, r.result.section === section, r.result.section);
}
r = await run([{ intent: 'moveSection', value: -1 }, { wait: 50 }]);
check('keyboard navigation wraps from Music to General', r.result.section === 'general', r.result.section);

const target = initialSource === 'appleMusic' ? 'spotify' : 'appleMusic';
r = await run([{ intent: 'section', value: 'music', keyboard: true }, { intent: 'source', value: target }, { wait: 500 }]);
check('player selection is confirmed natively', r.result.musicSource === target && r.result.requested === null, [r.result.musicSource, r.result.requested]);
r = await run([{ intent: 'source', value: initialSource }, { wait: 500 }]);
check('player selection returns to the original source', r.result.musicSource === initialSource, r.result.musicSource);
r = await run([{ call: 'receiveSnapshot', value: snapshot({ musicSource: initialSource, musicBusy: true }) }, { intent: 'source', value: target }, settle, { capture: 'settings-music-busy' }]);
// Polling may replace the injected snapshot after the refusal, so assert the refusal, not the injected flag.
check('player selection is refused while a music command is pending', r.result.musicSource === initialSource && r.result.requested === null, r.result);
r = await run([restore, settle]);
check('the real snapshot replaces the simulated lock', !r.result.musicBusy, r.result.musicBusy);

r = await run([{ intent: 'section', value: 'focus', keyboard: true }, { intent: 'durationInput', value: '0' }, { intent: 'durationCommit' }, settle, { capture: 'settings-focus-invalid' }]);
check('duration 0 is rejected with an error', r.result.durationError && r.result.focusMinutes === 25 && r.result.requested === null, r.result);
r = await run([{ intent: 'durationInput', value: '181' }, { intent: 'durationCommit' }, { wait: 50 }]);
check('duration 181 is rejected', r.result.durationError && r.result.focusMinutes === 25, r.result);
r = await run([{ intent: 'durationInput', value: '180' }, { intent: 'durationCommit' }, { wait: 500 }]);
check('duration 180 is saved', r.result.focusMinutes === 180 && r.result.durationDraft === null && !r.result.durationError, r.result);
r = await run([{ intent: 'preset', value: 25 }, { wait: 500 }]);
check('duration preset 25 is saved', r.result.focusMinutes === 25, r.result.focusMinutes);
r = await run([{ message: { action: 'settingsUpdate', changes: { focusMinutes: 181 } } }, settle, { capture: 'settings-error' }]);
check('native validation refuses 181 minutes and reports it', r.result.error?.code === 'invalid' && r.result.focusMinutes === 25 && r.result.saveStatus === 'error', r.result.error);
r = await run([restore, settle]);
check('a valid update clears the error', r.result.error === null, r.result.error);
r = await run([{ intent: 'activity', value: 'lightWork' }, { wait: 500 }]);
check('activity is confirmed natively', r.result.focusActivity === 'lightWork', r.result.focusActivity);
r = await run([{ intent: 'activity', value: 'deepWork' }, { wait: 500 }]);

r = await run([{ call: 'receiveSnapshot', value: snapshot({ focusLocked: true }) }, { intent: 'preset', value: 50 }, { intent: 'toggle', value: 'brainFMEnabled' }, settle, { capture: 'settings-focus-locked' }]);
check('a running focus session locks duration and Brain.fm', r.result.focusMinutes === 25 && r.result.requested === null, r.result);
await run([restore, settle]);

r = await run([{ intent: 'toggle', value: 'focusSound' }, { wait: 400 }]);
check('sound switch is confirmed natively', r.result.focusSound === false, r.result.focusSound);
r = await run([{ intent: 'toggle', value: 'focusSound' }, { wait: 400 }]);
r = await run([{ intent: 'focusNotifications' }, { wait: 500 }]);
check('timer notification opt-in is simulated in diagnostics', r.result.focusNotificationsEnabled && r.result.focusNotificationStatus === 'diagnostic', r.result);
r = await run([{ intent: 'focusNotifications' }, { wait: 500 }]);
check('timer notifications can be disabled', !r.result.focusNotificationsEnabled, r.result.focusNotificationsEnabled);

r = await run([{ intent: 'section', value: 'shelf', keyboard: true }, { intent: 'menu', value: 'shelfShortDays' }, settle, { capture: 'settings-shelf-menu' }]);
check('retention menu lists presets and Custom…', r.result.openMenu === 'shelfShortDays' && r.result.menuItems.join() === '1,3,7,14,30,custom', r.result.menuItems);
r = await run([{ intent: 'menuChoose', value: 'custom' }, { intent: 'retentionInput', key: 'shelfShortDays', value: '0' }, { intent: 'retentionCommit', value: 'shelfShortDays' }, settle, { capture: 'settings-shelf-invalid' }]);
check('retention 0 days is rejected', r.result.retentionErrors.shelfShortDays && r.result.shelfShortDays === 7, r.result);
r = await run([{ intent: 'retentionInput', key: 'shelfShortDays', value: '3651' }, { intent: 'retentionCommit', value: 'shelfShortDays' }, { wait: 50 }]);
check('retention 3651 days is rejected', r.result.retentionErrors.shelfShortDays && r.result.shelfShortDays === 7, r.result);
r = await run([{ intent: 'retentionInput', key: 'shelfShortDays', value: '3650' }, { intent: 'retentionCommit', value: 'shelfShortDays' }, { wait: 500 }]);
check('retention 3650 days is saved and the custom field closes', r.result.shelfShortDays === 3650 && !r.result.retentionCustom.length, r.result);
r = await run([{ intent: 'menu', value: 'shelfShortDays' }, { wait: 100 }]);
check('a custom retention stays listed in the menu', r.result.menuItems.includes('3650'), r.result.menuItems);
r = await run([{ intent: 'menuChoose', value: '7' }, { wait: 500 }]);
check('choosing a preset saves it', r.result.shelfShortDays === 7 && r.result.openMenu === null, r.result);

r = await run([{ intent: 'section', value: 'general', keyboard: true }, settle, { intent: 'menu', value: 'displayID' }, settle, { capture: 'settings-display-menu' }]);
check('display menu starts with Automatic', r.result.openMenu === 'displayID' && r.result.menuItems[0] === '' && !r.result.menuItems.includes('custom'), r.result.menuItems);
r = await run([{ intent: 'escape' }, { wait: 250 }]);
check('Escape closes the menu but not the window', r.result.openMenu === null && r.settingsVisible, [r.result.openMenu, r.settingsVisible]);
r = await run([{ intent: 'menu', value: 'displayID' }, { intent: 'menuKey', value: 'down' }, { intent: 'menuKey', value: 'up' }, { intent: 'menuKey', value: 'return' }, { wait: 400 }]);
check('menu keyboard selection keeps Automatic', r.result.openMenu === null && r.result.displayID === '', r.result);

r = await run([{ intent: 'toggle', value: 'openAtLogin' }, { wait: 400 }]);
check('open at login is simulated in diagnostics', r.result.openAtLogin === true, r.result.openAtLogin);
await run([{ intent: 'toggle', value: 'openAtLogin' }, { wait: 400 }]);
r = await run([{ intent: 'toggle', value: 'notificationBannersEnabled' }, { wait: 400 }]);
check('notification opt-in is confirmed while capture stays diagnostic', r.result.notificationBannersEnabled && r.result.notificationCaptureStatus === 'diagnostic', r.result);
r = await run([{ intent: 'toggle', value: 'notificationBannersEnabled' }, { wait: 400 }]);
check('notification opt-in can be withdrawn', r.result.notificationBannersEnabled === false, r.result.notificationBannersEnabled);

r = await run([{ intent: 'shortcutRecord' }, { wait: 150 }, { message: { action: 'testShortcutKey', keyCode: 3, modifiers: 0 } }, { wait: 150 }, { capture: 'settings-shortcut-recording' }]);
check('an unmodified key is rejected while recording continues', r.result.recordingShortcut && r.result.shortcutRecordingError.includes('Control'), r.result);
r = await run([{ message: { action: 'testShortcutKey', keyCode: 3, modifiers: 1179648 } }, { wait: 400 }]);
check('Command-Shift-F is recorded natively', !r.result.recordingShortcut && r.result.shortcut?.keyCode === 3 && r.result.shortcut?.modifiers === 768, r.result.shortcut);
r = await run([{ intent: 'shortcutReset' }, { wait: 400 }]);
check('reset restores Control-Option-L', r.result.shortcut?.keyCode === 37 && r.result.shortcut?.modifiers === 6144 && r.result.requested === null, r.result.shortcut);

r = await run([{ call: 'configure', value: { reducedMotion: true } }, { intent: 'section', value: 'focus' }, { wait: 50 }, { capture: 'settings-reduced-motion' }]);
check('reduced motion is applied', r.result.reducedMotion && r.result.section === 'focus', r.result.reducedMotion);
r = await run([{ call: 'configure', value: { reducedMotion: false } }, { intent: 'section', value: 'music', keyboard: true }, settle, { capture: 'settings-compact' }], { width: 700, height: 540 });
check('the window resizes to its minimum size', /\{700, 5\d\d\}/.test(r.settingsFrame), r.settingsFrame);
await run([settle], { width: 820, height: 620 });

const failed = checks.filter(c => !c.pass);
console.log(JSON.stringify({ passed: checks.length - failed.length, total: checks.length, failed }, null, 2));
if (failed.length) process.exitCode = 1;
