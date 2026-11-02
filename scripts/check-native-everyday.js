const checks = [];
const check = (name, pass) => checks.push({ name, pass: Boolean(pass) });
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const until = async predicate => { const deadline = performance.now() + 3500; while (!predicate() && performance.now() < deadline) await wait(20); return predicate(); };
const find = selector => document.querySelector(selector);
const post = body => webkit.messageHandlers.lilt.postMessage(body);
const nativeClick = async selector => {
  const r = find(selector).getBoundingClientRect();
  for (const phase of ['down', 'up']) { post({ action: 'testPointer', phase, x: r.x + r.width / 2, y: r.y + r.height / 2 }); await wait(45); }
};
const nativeBlank = async () => {
  const r = find('.notch-panel').getBoundingClientRect();
  for (let y = r.top + 4; y < r.bottom - 4; y += 8) for (let x = r.left + 4; x < r.right - 4; x += 8) {
    const target = document.elementFromPoint(x, y);
    if (!target || !find('#notch').contains(target) || target.closest('button, input, a, .focus-menu, .shelf-menu, .notch-wings, .notch-foot')) continue;
    for (const phase of ['down', 'up']) { post({ action: 'testPointer', phase, x, y }); await wait(45); }
    return;
  }
  throw new Error('No blank panel surface found');
};
post({ action: 'focusAction', command: 'reset' });
await until(() => Lilt.inspect().focus.phase === 'idle');
Lilt.setOpen(true); Lilt.setView('focus', { animate: false }); await wait(600);
for (const trigger of ['#focus-duration', '#focus-activity']) {
  await nativeClick(trigger); await wait(220);
  check(`${trigger} opens using native pointer events`, find(trigger).getAttribute('aria-expanded') === 'true');
  await nativeBlank(); await wait(200);
  check(`${trigger} blank click closes only dropdown`, Lilt.inspect().open && find(trigger).getAttribute('aria-expanded') === 'false');
  await nativeBlank(); await wait(600);
  check('second blank click folds Lilt', !Lilt.inspect().open);
  Lilt.setOpen(true); await wait(600);
}
await nativeClick('#focus-duration'); await wait(220);
post({ action: 'testOutsideInteraction' }); await wait(250);
check('native outside interaction dismisses dropdown first', Lilt.inspect().open && find('#focus-duration-menu').inert);
post({ action: 'testOutsideInteraction' }); await wait(600);
check('next native outside interaction folds Lilt', !Lilt.inspect().open);
Lilt.setOpen(true); await wait(600);
post({ action: 'focusConfigure', activity: 'deepWork', minutes: 1 });
await until(() => Lilt.inspect().focus.duration === 60);
await nativeClick('[data-action="focus"]');
await until(() => Lilt.inspect().focus.phase === 'running');
check('running timer offers five-minute extension', !find('[data-action="focus-extend"]').hidden && !find('[data-action="focus-extend"]').disabled);
post({ action: 'testFocus', remaining: 0 });
await until(() => Lilt.inspect().focus.phase === 'completed');
check('completion has clear actions without starting next phase', !find('[data-action="focus-end"]').hidden && Lilt.inspect().focus.remaining === 0);
await nativeClick('[data-action="focus-extend"]');
await until(() => Lilt.inspect().focus.phase === 'running');
check('five-minute extension starts native timer', Lilt.inspect().focus.remaining >= 298 && Lilt.inspect().focus.remaining <= 300 && Lilt.inspect().focus.totalDuration === 360);
await nativeClick('[data-action="focus"]'); await until(() => Lilt.inspect().focus.phase === 'paused');
const paused = Lilt.inspect().focus.remaining;
await nativeClick('[data-action="focus-extend"]'); await wait(120);
check('paused extension adds time without resuming', Lilt.inspect().focus.phase === 'paused' && Lilt.inspect().focus.remaining === paused + 300);
post({ action: 'focusAction', command: 'reset' });
await until(() => Lilt.inspect().focus.phase === 'idle');
post({ action: 'focusIntervalsConfigure', workMinutes: 1, restMinutes: 5 });
await until(() => Lilt.inspect().focus.interval?.workMinutes === 1);
await nativeClick('[data-action="focus"]'); await until(() => Lilt.inspect().focus.phase === 'running');
post({ action: 'testFocus', remaining: 0 }); await until(() => Lilt.inspect().focus.phase === 'completed');
check('interval completion labels the explicit next action', find('[data-action="focus"]').getAttribute('aria-label') === 'Start break');
await nativeClick('[data-action="focus-end"]'); await until(() => Lilt.inspect().focus.phase === 'idle');
check('End leaves no pending interval', Lilt.inspect().focus.interval === null);
check('no page errors', Lilt.inspect().errors.length === 0);
return { checks, state: Lilt.inspect() };
