const notch = document.querySelector('#notch');
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const frames = [];
const points = [[0,0],[.035,.062],[.085,.24],[.145,.5],[.215,.76],[.29,.93],[.38,1.024],[.46,1.042],[.56,1.03],[.7,1.008],[1,1]];
function spring(t) {
  t = Math.max(0,Math.min(1,t));
  let i=1; while (points[i][0]<t) i++;
  const [a,x]=points[i-1], [b,y]=points[i];
  return x+(y-x)*(t-a)/(b-a);
}
Lilt.configure({reducedMotion:false}); Lilt.setView('music'); Lilt.setOpen(false); await wait(650);
const start = notch.getBoundingClientRect();
Lilt.setOpen(true);
await new Promise(resolve => {
 const began=performance.now();
 function sample() {
  const widthAnimation=notch.getAnimations().find(a=>a.transitionProperty==='width');
  const r=notch.getBoundingClientRect();
  const p=getComputedStyle(document.querySelector('.notch-panel'));
  if(widthAnimation) frames.push({time:widthAnimation.currentTime,width:r.width,height:r.height,opacity:Number(p.opacity),blur:p.filter});
  if(performance.now()-began<650)requestAnimationFrame(sample);else resolve();
 }
 requestAnimationFrame(sample);
});
const end = notch.getBoundingClientRect();
const errors=frames.filter(f=>typeof f.time==='number').map(f=>Math.abs(f.width-(start.width+(end.width-start.width)*spring(f.time/520))));
const peak=frames.reduce((a,b)=>a.width>b.width?a:b);
const checks=[
 {name:'native open overshoots and settles',pass:peak.width>end.width+4 && Math.abs(end.width-500)<.1},
 {name:'native curve follows reference within 1 CSS px',pass:Math.max(...errors)<1},
 {name:'content stays hidden before 120 ms',pass:frames.filter(f=>f.time>10&&f.time<110).every(f=>f.opacity===0)},
 {name:'content reaches full opacity',pass:getComputedStyle(document.querySelector('.notch-panel')).opacity==='1'},
];
return {checks,start:start.toJSON(),end:end.toJSON(),peak,maxWidthError:Math.max(...errors),frames};
