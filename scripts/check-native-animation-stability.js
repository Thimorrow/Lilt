const Lilt = window.Lilt;
const externalOpenChanges = [];
// Keep outside desktop clicks out of this controlled geometry probe.
window.Lilt = { ...Lilt, setOpen(open) { externalOpenChanges.push(open); } };
try {
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const frame = () => new Promise(requestAnimationFrame);
const notch = document.querySelector('#notch');
const panel = document.querySelector('#notch-panel');
const tabs = document.querySelector('.tabs');
const checks = [];
const check = (name, pass) => checks.push({ name, pass: Boolean(pass) });
const rect = element => element.getBoundingClientRect().toJSON();
const same = (a, b) => ['x', 'y', 'width', 'height'].every(key => Math.abs(a[key] - b[key]) < .1);
const marker = () => {
  const style = getComputedStyle(tabs, '::before');
  return new DOMMatrixReadOnly(style.transform).m41 / (parseFloat(style.width) + 2);
};
Lilt.configure({ reducedMotion: false });
Lilt.setView('music', { animate: false });
Lilt.setOpen(true); await wait(650);
const resting = { panel: rect(panel), play: rect(document.querySelector('[data-action="play"]')) };
Lilt.setOpen(false); await wait(650);
const compact = document.querySelector('.notch-compact');
const compactRect = rect(compact);
check('compact wings remain hit-testable through the content clip', [compactRect.left + 20, compactRect.right - 20].every(x => compact.contains(document.elementFromPoint(x, compactRect.top + compactRect.height / 2))));
Lilt.setOpen(true);
const opening = document.getAnimations().filter(animation => animation.effect?.target === notch || animation.effect?.target === panel);
opening.forEach(animation => animation.pause());
await wait(30);
const samples = [];
for (const time of [40, 100, 160, 240, 360, 520]) {
  opening.forEach(animation => { animation.currentTime = time; });
  await frame();
  samples.push({ time, shell: rect(notch), panel: rect(panel), play: rect(document.querySelector('[data-action="play"]')) });
}
check('content layout stays fixed while the shell morphs', samples.every(sample => same(sample.panel, resting.panel) && same(sample.play, resting.play)));
check('shell still grows, overshoots and settles', samples[0].shell.width < samples.at(-1).shell.width - 50 && samples.some(sample => sample.shell.width > samples.at(-1).shell.width + 4));
opening.forEach(animation => animation.finish());
await wait(50);
const x = resting.play.x + resting.play.width / 2, y = resting.play.y + resting.play.height / 2;
Lilt.swipeGesture('begin', -50, 0, 0, x, y);
await frame();
const beforeRelease = marker();
const visible = [...document.querySelectorAll('.view')].filter(view => getComputedStyle(view).visibility === 'visible');
check('swipe composites no more than the two intersecting pages', visible.length === 2);
check('swipe does not rasterize an animated blur', [...document.querySelectorAll('.view')].every(view => ['none', 'blur(0px)'].includes(getComputedStyle(view).filter)));
let inheritedWrites = 0;
const observer = new MutationObserver(records => { inheritedWrites += records.length; });
observer.observe(notch, { attributes: true, attributeFilter: ['style'] });
Lilt.swipeGesture('change', -20, 0, 0, x, y);
await frame(); await Promise.resolve();
check('swipe position does not invalidate the whole notch style subtree', inheritedWrites === 0);
observer.disconnect();
const beforeEnd = marker();
Lilt.swipeGesture('end', 0, 0, 1, x, y);
check('release keeps marker and content continuous', Math.abs(marker() - beforeEnd) < .001 && beforeRelease > 0 && beforeEnd < 1);
await wait(450);
check('swipe finishes on the intended view', Lilt.inspect().view === 'focus' && Math.abs(marker() - 1) < .001);
Lilt.setOpen(false);
Lilt.configure({ reducedMotion: true });
Lilt.setOpen(true);
check('reduced motion still opens immediately', document.getAnimations().length === 0 && same(rect(panel), resting.panel));
const originalWidth = parseFloat(getComputedStyle(notch).getPropertyValue('--hw'));
const originalHeight = parseFloat(getComputedStyle(notch).getPropertyValue('--hd'));
const originalScale = notch.style.getPropertyValue('--k');
const geometries = [];
for (const [hardwareWidth, hardwareHeight, scale] of [[188, 24, .85], [320, 32, 1], [500, 64, 1.15]]) {
  Lilt.configure({ hardwareWidth, hardwareHeight });
  notch.style.setProperty('--k', scale);
  const shell = rect(notch), content = rect(panel);
  geometries.push({ hardwareWidth, hardwareHeight, scale, shell, content });
}
check('fixed content matches the shell across zoom and notch geometries', geometries.every(({ shell, content }) => same(shell, content)));
Lilt.configure({ hardwareWidth: originalWidth, hardwareHeight: originalHeight });
if (originalScale) notch.style.setProperty('--k', originalScale); else notch.style.removeProperty('--k');
Lilt.configure({ reducedMotion: false });
document.querySelector('#focus-duration').click();
const custom = document.querySelector('[data-action="focus-custom"]');
const customRect = rect(custom);
check('duration menu stays above the footer hit targets', custom.contains(document.elementFromPoint(customRect.left + customRect.width / 2, customRect.top + customRect.height / 2)));
document.querySelector('#focus-duration-menu').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
check('menu Escape preserves the open panel', Lilt.inspect().open && document.querySelector('#focus-duration-menu').hidden);
check('no runtime errors', Lilt.inspect().errors.length === 0);
return { checks, resting, samples, geometries, externalOpenChanges, simulatedGesture: true, errors: Lilt.inspect().errors };
} finally { window.Lilt = Lilt; }
