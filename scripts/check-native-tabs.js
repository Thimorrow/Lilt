const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const frame = () => new Promise(requestAnimationFrame);
const checks = [];
const check = (name, pass) => checks.push({ name, pass: Boolean(pass) });
const notch = document.querySelector('#notch');
const views = ['music', 'focus', 'shelf'];
const panels = views.map(view => document.querySelector(`#view-${view}`));
const tabs = document.querySelector('.tabs');
const button = view => document.querySelector(`#tab-${view}`);
const pointerClick = view => button(view).dispatchEvent(new MouseEvent('click', { bubbles: true, detail: 1 }));
const translate = transform => transform === 'none' ? 0 : new DOMMatrixReadOnly(transform).m41;
const read = element => {
  const style = getComputedStyle(element);
  const matrix = new DOMMatrixReadOnly(style.transform === 'none' ? undefined : style.transform);
  return { opacity: Number(style.opacity), x: matrix.m41, y: matrix.m42, scale: matrix.m11, visibility: style.visibility, inert: element.inert, accessible: element.getAttribute('aria-hidden') !== 'true' };
};
const pill = () => translate(getComputedStyle(tabs, '::before').transform);
const settled = view => panels.every((element, index) => {
  const value = read(element);
  return views[index] === view
    ? value.opacity === 1 && Math.abs(value.x) < .1 && Math.abs(value.y) < .1 && Math.abs(value.scale - 1) < .001 && value.visibility === 'visible' && !value.inert && value.accessible
    : value.opacity === 0 && value.visibility === 'hidden' && value.inert && !value.accessible;
});
const motion = () => document.getAnimations().filter(animation => panels.includes(animation.effect?.target) || animation.effect?.target === tabs);
Lilt.configure({ reducedMotion: false });
Lilt.setView('music', { animate: false });
Lilt.setOpen(true);
await wait(650);
const baseline = Lilt.inspect();
const geometry = { notch: notch.getBoundingClientRect().toJSON(), footer: document.querySelector('.notch-foot').getBoundingClientRect().toJSON() };
const musicPlay = document.querySelector('[data-action="play"]').getBoundingClientRect().toJSON();
check('initial panel alone is visible and accessible', settled('music'));
const routes = [['music', 'focus'], ['focus', 'shelf'], ['shelf', 'focus'], ['focus', 'music'], ['music', 'shelf'], ['shelf', 'music']];
const transitions = [];
for (const [from, to] of routes) {
  Lilt.setView(from, { animate: false });
  await frame();
  const source = panels[views.indexOf(from)];
  const destination = panels[views.indexOf(to)];
  const startPill = pill();
  pointerClick(to);
  check(`${from} to ${to}: selection and input ownership change immediately`, Lilt.inspect().view === to && button(to).getAttribute('aria-selected') === 'true' && source.inert && !destination.inert && source.getAttribute('aria-hidden') === 'true');
  source.querySelector('button')?.focus();
  check(`${from} to ${to}: outgoing controls cannot receive focus`, !source.contains(document.activeElement));
  const samples = [];
  const began = performance.now();
  while (performance.now() - began < 300) {
    await frame();
    samples.push({ time: performance.now() - began, from: read(source), to: read(destination), pill: pill(), width: notch.getBoundingClientRect().width, height: notch.getBoundingClientRect().height, footer: document.querySelector('.notch-foot').getBoundingClientRect().y });
  }
  const endPill = pill();
  check(`${from} to ${to}: outgoing and incoming labels never overlap`, samples.every(sample => sample.from.opacity <= .02 || sample.to.opacity <= .02));
  check(`${from} to ${to}: content settles in depth without a sideways slide`, samples.every(sample => Math.abs(sample.from.x) < .1 && Math.abs(sample.to.x) < .1) && samples.some(sample => sample.to.opacity > .05 && sample.to.y > .1 && sample.to.y < 4 && sample.to.scale < 1 && sample.to.scale > .98));
  check(`${from} to ${to}: outgoing content clears before the new content settles`, samples.some(sample => sample.time < 140 && sample.from.opacity === 0 && sample.to.opacity > .1 && sample.to.opacity < 1));
  check(`${from} to ${to}: selection pill travels between tabs`, Math.abs(endPill - startPill) > 40 && samples.some(sample => sample.pill > Math.min(startPill, endPill) + .5 && sample.pill < Math.max(startPill, endPill) - .5));
  check(`${from} to ${to}: panel and footer never resize or shift`, samples.every(sample => Math.abs(sample.width - geometry.notch.width) < .1 && Math.abs(sample.height - geometry.notch.height) < .1 && Math.abs(sample.footer - geometry.footer.y) < .1));
  check(`${from} to ${to}: only the destination remains visible`, settled(to) && motion().length === 0);
  if (to === 'music' || to === 'focus') {
    const play = document.querySelector(`[data-action="${to === 'music' ? 'play' : 'focus'}"]`).getBoundingClientRect();
    check(`${to}: play button keeps the same horizontal and vertical position`, Math.abs(play.x - musicPlay.x) < .1 && Math.abs(play.y - musicPlay.y) < .1 && play.width === musicPlay.width && play.height === musicPlay.height);
  }
  transitions.push({ from, to, startPill, endPill, samples });
}
Lilt.setView('music', { animate: false });
await frame();
pointerClick('focus');
await wait(60);
const reversingAnimations = motion();
reversingAnimations.forEach(animation => animation.pause());
await Promise.all(reversingAnimations.map(animation => animation.ready));
const beforeReverse = { music: read(panels[0]), focus: read(panels[1]), pill: pill() };
pointerClick('music');
const afterReverse = { music: read(panels[0]), focus: read(panels[1]), pill: pill() };
check('reversing mid-flight continues from the visible position', Math.abs(beforeReverse.music.y - afterReverse.music.y) < .1 && Math.abs(beforeReverse.focus.y - afterReverse.focus.y) < .1 && Math.abs(beforeReverse.music.scale - afterReverse.music.scale) < .001 && Math.abs(beforeReverse.focus.scale - afterReverse.focus.scale) < .001 && Math.abs(beforeReverse.pill - afterReverse.pill) < 1 && Math.abs(beforeReverse.music.opacity - afterReverse.music.opacity) < .02 && Math.abs(beforeReverse.focus.opacity - afterReverse.focus.opacity) < .02);
await wait(300);
check('reversed transition settles on the last click', settled('music'));
pointerClick('focus');
await wait(60);
const activeAnimations = motion();
pointerClick('focus');
check('clicking the selected tab does not restart motion', activeAnimations.length > 0 && activeAnimations.every(animation => motion().includes(animation)));
for (const view of ['shelf', 'music', 'focus', 'shelf', 'music', 'focus']) {
  pointerClick(view);
  await wait(35);
}
await wait(300);
await frame();
const rapid = { panels: panels.map(read), animations: motion().map(animation => ({ target: animation.effect.target.className, property: animation.transitionProperty, state: animation.playState, time: animation.currentTime })), tabStops: views.filter(view => button(view).tabIndex === 0) };
check('rapid clicks settle with one active panel and one tab stop', settled('focus') && rapid.tabStops.join() === 'focus' && rapid.animations.length === 0);
for (const [key, expected] of [['ArrowRight', 'shelf'], ['ArrowRight', 'music'], ['End', 'shelf'], ['Home', 'music'], ['ArrowLeft', 'shelf']]) {
  document.activeElement.blur();
  button(Lilt.inspect().view).focus();
  button(Lilt.inspect().view).dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }));
  check(`${key} selects ${expected} immediately without panel or pill motion`, settled(expected) && document.activeElement === button(expected) && motion().length === 0);
}
button('music').click();
check('keyboard-style activation also switches without motion', settled('music') && motion().length === 0);
pointerClick('focus');
await wait(60);
check('pointer movement is running before reduced motion is enabled', motion().length > 0);
Lilt.configure({ reducedMotion: true });
check('enabling reduced motion mid-transition settles all contents immediately', settled('focus') && document.getAnimations().length === 0);
pointerClick('shelf');
check('reduced motion disables movement and fades for panel and pill', settled('shelf') && document.getAnimations().length === 0);
Lilt.configure({ reducedMotion: false });
await frame();
check('restoring normal motion does not replay a transition', settled('shelf') && motion().length === 0);
Lilt.setOpen(false);
await wait(600);
Lilt.setView('music');
check('switching compact views does not animate invisible contents', settled('music') && motion().length === 0);
Lilt.setOpen(true);
await wait(650);
check('reopening shows the selected panel correctly', settled('music') && Lilt.inspect().open);
const final = Lilt.inspect();
check('tab motion preserves music, focus and shelf state', JSON.stringify({ ...final.music, since: 0 }) === JSON.stringify({ ...baseline.music, since: 0 }) && JSON.stringify(final.focus) === JSON.stringify(baseline.focus) && JSON.stringify(final.shelf) === JSON.stringify(baseline.shelf));
check('tab switching sends no focus playback request', final.focus.pending === null && final.focus.deadline === baseline.focus.deadline);
check('no runtime errors', final.errors.length === 0);
return { checks, geometry, transitions, beforeReverse, afterReverse, rapid, state: final };
