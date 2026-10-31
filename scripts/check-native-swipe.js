const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const checks = [];
const check = (name, pass) => checks.push({ name, pass: Boolean(pass) });
const point = selector => {
  const rect = document.querySelector(selector).getBoundingClientRect();
  return [rect.left + rect.width / 2, rect.top + rect.height / 2];
};
Lilt.setOpen(true);
Lilt.setView('music');
await wait(600);
let [x, y] = point('#tab-focus');
check('swipe moves to next tab', Lilt.swipeTab(1, x, y) && Lilt.inspect().view === 'focus');
check('swipe moves to previous tab', Lilt.swipeTab(-1, x, y) && Lilt.inspect().view === 'music');
check('first tab does not wrap', !Lilt.swipeTab(-1, x, y) && Lilt.inspect().view === 'music');
Lilt.swipeGesture('begin', -15, 0, 0, x, y);
Lilt.swipeGesture('change', -10, 0, 0, x, y);
await new Promise(requestAnimationFrame);
check('views follow the gesture before a tab is selected', Lilt.inspect().view === 'music' &&
  Math.abs(new WebKitCSSMatrix(getComputedStyle(document.querySelector('#view-music')).transform).m41 *
    (document.querySelector('#view-music').getBoundingClientRect().width / document.querySelector('#view-music').offsetWidth) + 25) < 1 &&
  getComputedStyle(document.querySelector('#view-focus')).visibility === 'visible');
Lilt.swipeGesture('end', 0, 0, 0, x, y);
await wait(300);
check('short gesture returns to the original tab', Lilt.inspect().view === 'music' &&
  !document.querySelector('#view-music').style.transform);
Lilt.swipeGesture('begin', 45, 0, 0, x, y);
await new Promise(requestAnimationFrame);
check('outside edge resists without wrapping', Lilt.inspect().view === 'music' && document.querySelector('#view-music').style.transform);
Lilt.swipeGesture('end', 0, 0, -1, x, y);
await wait(350);
check('outside edge settles to original page', Lilt.inspect().view === 'music' && !document.querySelector('#view-music').style.transform);
Lilt.swipeGesture('begin', -20, 0, 0, x, y);
Lilt.swipeGesture('change', -25, 0, 0, x, y);
Lilt.swipeGesture('end', 0, 0, 1, x, y);
check('completed gesture selects the next tab', Lilt.inspect().view === 'focus');
await wait(300);
check('gesture settles with only selected view accessible', !document.querySelector('#view-focus').inert && document.querySelector('#view-music').inert &&
  !document.querySelector('#view-focus').style.transform &&
  getComputedStyle(document.querySelector('#view-music')).visibility === 'hidden');
// Interrupt the return animation without allowing a frame-one jump.
Lilt.swipeGesture('begin', -70, 0, 0, x, y);
await new Promise(requestAnimationFrame);
Lilt.swipeGesture('cancel', 0, 0, 0, x, y);
await wait(32);
const movingBefore = document.querySelector('#view-focus').getBoundingClientRect().left;
Lilt.swipeGesture('begin', 0, 0, 0, x, y);
const movingAfter = document.querySelector('#view-focus').getBoundingClientRect().left;
check('new gesture takes over live spring position without a jump', Math.abs(movingBefore - movingAfter) < 1);
Lilt.swipeGesture('change', 15, 0, 0, x, y);
await new Promise(requestAnimationFrame);
const musicLeft = document.querySelector('#view-music').getBoundingClientRect().left;
const focusRect = document.querySelector('#view-focus').getBoundingClientRect();
check('adjacent pages stay attached during reversal', Math.abs(focusRect.left - musicLeft - focusRect.width) < 1);
Lilt.swipeGesture('cancel', 0, 0, 0, x, y);
await wait(350);
check('cancelled interrupted gesture settles cleanly', Lilt.inspect().view === 'focus' && !document.querySelector('#view-focus').style.transform);
Lilt.swipeGesture('begin', -50, 0, 0, x, y);
Lilt.swipeGesture('change', 100, 0, 0, x, y);
Lilt.swipeGesture('end', 0, 0, -1, x, y);
check('reversing gesture selects the final direction', Lilt.inspect().view === 'music');
await wait(300);
Lilt.swipeGesture('begin', -45, 0, 0, x, y);
Lilt.swipeGesture('end', 0, 0, 1, x, y);
Lilt.configure({ reducedMotion:true });
check('enabling reduced motion during settling cleans inline motion', Lilt.inspect().view === 'focus' &&
  !document.querySelector('#view-focus').style.transform && !document.querySelector('#view-music').style.transform);
Lilt.configure({ reducedMotion:false });
Lilt.setView('music', { animate:false });
Lilt.swipeGesture('begin', -12, 0, 0, x, y, 100);
await new Promise(requestAnimationFrame);
const trackedView = document.querySelector('#view-music');
const beforeBurst = trackedView.style.transform;
let transformWrites = 0;
const writes = new MutationObserver(records => { transformWrites += records.length; });
writes.observe(trackedView, { attributes:true, attributeFilter:['style'] });
for (let sample = 1; sample <= 80; sample++) Lilt.swipeGesture('change', -.5, 0, 0, x, y, 100 + sample / 240);
check('input burst does not repeatedly repaint between display frames', trackedView.style.transform === beforeBurst);
await new Promise(requestAnimationFrame);
await Promise.resolve();
check('tab marker follows the same continuous position as the content',
  Number(document.querySelector('#notch').style.getPropertyValue('--tab-index')) > 0 &&
  Number(document.querySelector('#notch').style.getPropertyValue('--tab-index')) < 1);
check('input burst paints one accumulated position per display frame', transformWrites === 1 &&
  Math.abs(new WebKitCSSMatrix(getComputedStyle(trackedView).transform).m41 *
    (trackedView.getBoundingClientRect().width / trackedView.offsetWidth) + 52) < 1);
writes.disconnect();
Lilt.swipeGesture('cancel', 0, 0, 0, x, y, 100.5);
await wait(400);
check('batched input cancellation settles cleanly', !trackedView.style.transform && Lilt.inspect().view === 'music');
Lilt.setView('shelf');
await wait(350);
check('last tab does not wrap', !Lilt.swipeTab(1, x, y) && Lilt.inspect().view === 'shelf');
Lilt.receiveShelfSnapshot({ items: [{ id:'fixture', name:'Fixture.txt', location:'Test', available:true, kind:'TXT' }], message:null });
[x, y] = point('.files');
Lilt.swipeGesture('begin', 0, 18, 0, x, y);
Lilt.swipeGesture('change', 2, 36, 0, x, y);
Lilt.swipeGesture('end', 0, 0, 0, x, y);
check('vertical shelf scrolling does not switch tabs', Lilt.inspect().view === 'shelf');
Lilt.swipeGesture('begin', 20, 0, 0, x, y);
Lilt.swipeGesture('change', 25, 0, 0, x, y);
Lilt.swipeGesture('end', 0, 0, -1, x, y);
check('horizontal gesture over the shelf list switches tabs', Lilt.inspect().view === 'focus');
await wait(300);
Lilt.setView('shelf', { animate:false });
const scrollArea = document.createElement('div');
scrollArea.style.cssText = 'position:absolute;left:30px;top:40px;width:80px;height:30px;overflow-x:auto;z-index:10';
const scrollContent = document.createElement('div');
scrollContent.style.cssText = 'width:240px;height:20px';
scrollArea.append(scrollContent);
document.querySelector('#notch-panel').append(scrollArea);
[x, y] = point('.files');
const scrollRect = scrollArea.getBoundingClientRect();
check('horizontal scroll area is excluded', !Lilt.swipeTab(-1, scrollRect.left + 10, scrollRect.top + 10) && Lilt.inspect().view === 'shelf');
scrollArea.remove();
Lilt.setDragging(true);
[x, y] = point('#tab-focus');
check('file drag prevents navigation', !Lilt.swipeTab(-1, x, y) && Lilt.inspect().view === 'shelf');
Lilt.setDragging(false);
Lilt.swipeGesture('begin', 50, 0, 0, x, y);
Lilt.setDragging(true);
check('file drag cancels live swipe', !document.querySelector('#view-shelf').style.transform);
Lilt.setDragging(false);
Lilt.configure({ reducedMotion:true });
check('reduced motion keeps gesture available', Lilt.swipeTab(-1, x, y) && Lilt.inspect().view === 'focus');
check('reduced motion does not animate tab content', !document.querySelector('#view-focus').getAnimations().length);
Lilt.setOpen(false);
check('closed notch ignores gestures', !Lilt.swipeTab(-1, x, y));
Lilt.configure({ reducedMotion:false });
return { checks, simulatedGesture: true, errors: Lilt.inspect().errors };
