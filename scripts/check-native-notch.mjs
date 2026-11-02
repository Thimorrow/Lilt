// Drives an isolated diagnostic Lilt (--ui-test-dir DIR, simulated players) through native step lists
// and asserts on the returned model state. Usage: node scripts/check-native-notch.mjs DIR
import { readFile, writeFile, rename, mkdir, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { join, resolve } from 'node:path';

const dir = resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw new Error('Usage: node scripts/check-native-notch.mjs TEST_DIRECTORY');
const fixtures = join(dir, 'data', 'fixtures');
await mkdir(join(fixtures, 'folder'), { recursive: true });
for (const name of ['first.txt', 'second.txt', 'folder/inner.txt']) await writeFile(join(fixtures, name), name);

async function run(steps) {
  const id = randomUUID();
  await writeFile(join(dir, 'command.next.json'), JSON.stringify({ id, steps }));
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
const swipe = (dx, accepted, count = 6) => {
  let time = 1000 + Math.random();
  const steps = [{ swipe: { phase: 'begin', dx: Math.sign(dx) * 2, dy: 0, x: 340, y: 110, time } }];
  for (let i = 0; i < count; i++) steps.push({ swipe: { phase: 'change', dx, dy: 0, x: 340, y: 110, time: time += 0.016 } });
  steps.push({ swipe: { phase: 'end', dx: 0, dy: 0, accepted, x: 340, y: 110, time: time + 0.016 } }, { wait: 700 });
  return steps;
};
const reset = [{ call: 'configure', value: { reducedMotion: false } }, { intent: 'escape' }, { call: 'setOpen', value: false }, { wait: 650 }];

let r = await run([...reset, { capture: 'check-compact' }]);
check('folds to the compact hardware size', !r.result.open && r.result.size.height === r.result.hardware.height, r.result.size);
check('compact surface is the hit region', r.surfaceRect.includes(`${r.result.size.width}`), r.surfaceRect);
check('panel touches screen top and covers menu bar', r.nativeChecks.every(c => c.pass), r.nativeChecks);

r = await run([{ intent: 'userOpen' }, { wait: 700 }, { capture: 'check-open' }]);
check('opens to max(500, hardware + 260) wide', r.result.open && r.result.size.width === Math.min(648, Math.max(500, r.result.hardware.width + 260)), r.result.size);
check('open surface accepts pointer input', r.surfaceRect.includes(`${r.result.size.width}`), r.surfaceRect);

for (const view of ['focus', 'shelf', 'music']) {
  r = await run([{ call: 'setView', value: view }, { wait: 350 }]);
  check(`tab ${view} is native and UI authority`, r.result.view === view && r.selectedNativeView === view, [r.result.view, r.selectedNativeView]);
}

r = await run([{ call: 'setView', value: 'music' }, { wait: 300 }, ...swipe(-12, 1)]);
check('a swipe past 40 pt commits to the next page', r.result.view === 'focus' && r.result.swipePosition === null, r.result);
r = await run([...swipe(4, 0, 3)]);
check('a short swipe returns to its starting page', r.result.view === 'focus', r.result.view);
r = await run([{ call: 'setView', value: 'music' }, { wait: 300 }, ...swipe(20, -1, 12)]);
check('the first page rubber-bands instead of wrapping', r.result.view === 'music' && r.result.swipePosition === null, r.result.view);

r = await run([{ call: 'setView', value: 'focus' }, { wait: 300 }, { intent: 'focusMenu', value: 'duration' }, { wait: 300 }]);
check('duration dropdown opens', r.result.focusMenu === 'duration', r.result.focusMenu);
r = await run([{ intent: 'outsideClick' }, { wait: 250 }]);
check('an outside click closes only the dropdown', r.result.focusMenu === null && r.result.open, r.result);
r = await run([{ intent: 'focusMenu', value: 'activity' }, { wait: 250 }, { intent: 'escape' }, { wait: 200 }]);
check('Escape closes the dropdown first', r.result.focusMenu === null && r.result.open, r.result);
r = await run([{ intent: 'escape' }, { wait: 650 }]);
check('a second Escape folds the notch', !r.result.open, r.result.open);

r = await run([{ intent: 'userOpen' }, { call: 'setView', value: 'shelf' }, { message: { action: 'shelfAction', command: 'clear' } },
  { message: { action: 'testShelfPaste', names: ['first.txt', 'folder', 'second.txt'] } },
  { message: { action: 'shelfAction', command: 'paste' } }, { wait: 800 }, { capture: 'check-shelf' }]);
const ids = r.result.shelf.ids;
check('pasted fixtures appear as shelf references', ids.length === 3, ids);
check('visible rows publish native drag regions', r.shelfDragRegionCount === 3, r.shelfDragRegionCount);
r = await run([{ intent: 'selectShelf', value: ids[0] }, { intent: 'selectShelf', value: ids[2], range: true }, { wait: 200 }]);
check('shift selection covers the contiguous range', r.result.shelf.selected.length === 3, r.result.shelf.selected);
r = await run([{ intent: 'shelfMenu', value: ids[1] }, { wait: 300 }, { capture: 'check-shelf-menu' }]);
check('the file menu acts on the whole selection', r.result.shelfMenu?.ids.length === 3, r.result.shelfMenu);
check('drag regions pause while the file menu is open', r.shelfDragRegionCount === 0, r.shelfDragRegionCount);
r = await run([{ intent: 'outsideClick' }, { wait: 250 }, { message: { action: 'shelfAction', command: 'clear' } }, { wait: 300 }]);
check('clearing removes references', r.result.shelf.ids.length === 0 && r.result.open, r.result.shelf);

const banner = { action: 'testNotification', source: 'Synthetic', title: '<b>Plain</b>', body: 'Body text', app: 'com.apple.finder' };
r = await run([{ message: banner }, { wait: 200 }]);
check('a banner never covers an open panel', !r.result.notification.visible && r.notificationPending, r);
r = await run([{ call: 'setOpen', value: false }, { wait: 1500 }, { capture: 'check-banner' }]);
check('a queued banner opens the closed notch', r.result.notification.visible && r.result.open && r.notificationVisible && !r.notificationPending, r.result);
check('banner shows the app picture', r.result.notification.hasImage, r.result.notification);
check('banner arrival does not take key focus', r.notificationAcceptsKey === false, r.notificationAcceptsKey);
r = await run([{ call: 'setView', value: 'music' }, { wait: 300 }]);
check('choosing a tab takes over the banner and keeps Lilt open', !r.result.notification.visible && r.result.open && !r.notificationVisible, r.result);

// A finished agent turn, written exactly as `Lilt --notify` writes it, reaches the notch once.
await mkdir(join(dir, 'data', 'inbox'), { recursive: true });
const agent = { source: 'Codex', project: 'check-project', message: 'Finished the check.', app: '', created: Date.now() / 1000 };
await writeFile(join(dir, 'data', 'inbox', '.agent.tmp'), JSON.stringify(agent));
await rename(join(dir, 'data', 'inbox', '.agent.tmp'), join(dir, 'data', 'inbox', `${randomUUID()}.json`));
r = await run([{ call: 'setOpen', value: false }, { wait: 1800 }, { capture: 'check-agent-banner' }]);
check('an agent inbox message opens a banner', r.result.notification.visible && r.result.notification.hasText, r.result.notification);
check('the inbox file is consumed', (await readdir(join(dir, 'data', 'inbox'))).filter(n => n.endsWith('.json')).length === 0);
r = await run([{ message: { action: 'testNotification', clear: true } }, { wait: 650 }, { call: 'setOpen', value: true }, { wait: 650 }]);

r = await run([{ call: 'configure', value: { reducedMotion: true } }, { call: 'setView', value: 'music' }, { wait: 100 },
  { swipe: { phase: 'begin', dx: -20, dy: 0, x: 340, y: 110, time: 1 } }, { swipe: { phase: 'change', dx: -30, dy: 0, x: 340, y: 110, time: 1.02 } }]);
check('reduced motion never tracks the strip', r.result.swipePosition === null, r.result.swipePosition);
r = await run([{ swipe: { phase: 'end', dx: 0, dy: 0, accepted: 1, x: 340, y: 110, time: 1.05 } }, { wait: 50 }]);
check('reduced motion still switches pages immediately', r.result.view === 'focus', r.result.view);
await run(reset);

const failed = checks.filter(c => !c.pass);
console.log(JSON.stringify({ passed: checks.length - failed.length, total: checks.length, failed }, null, 2));
if (failed.length) process.exitCode = 1;
