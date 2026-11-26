// The live demo in the page header: a small port of what the app does, drawn
// on a canvas that sits over the pretend desktop. Snow lands on anything marked
// data-snow, and slides off when that thing moves.
(() => {
  'use strict';

  const canvas = document.getElementById('sky');
  if (!canvas || !canvas.getContext) return;
  const hero = canvas.parentElement;
  const ctx = canvas.getContext('2d');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  const state = { style: 'c9', palette: 'classic', pattern: 'twinkle', snow: 0.45, playing: !reducedMotion.matches };
  let W = 0, H = 0, DPR = 1;
  let now = 0;

  const rand = (a, b) => a + Math.random() * (b - a);
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const hash = (a, b) => {
    let x = Math.imul(a | 0, 73856093) ^ Math.imul(b | 0, 19349663);
    x = Math.imul(x ^ (x >>> 15), 0x85ebca6b);
    x = Math.imul(x ^ (x >>> 13), 0xc2b2ae35);
    return ((x ^ (x >>> 16)) >>> 0) / 4294967296;
  };
  const noise = (x, seed) => {
    const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
    return hash(i, seed) + (hash(i + 1, seed) - hash(i, seed)) * u;
  };

  // ---------- Lights ----------

  const PALETTES = {
    classic: [[255, 46, 40], [255, 200, 36], [34, 220, 86], [44, 110, 255], [255, 116, 26]],
    warm: [[255, 206, 130]],
    candy: [[255, 40, 46], [255, 246, 236]],
    icy: [[78, 160, 255], [220, 243, 255], [104, 232, 255]],
  };
  const STYLES = {
    c9: { w: 13, h: 26, pitch: 44, per: 3, sag: 8 },
    mini: { w: 7.5, h: 16, pitch: 26, per: 4, sag: 6 },
    globe: { w: 17, h: 21, pitch: 50, per: 3, sag: 8 },
  };
  let bulbs = [];
  let wire = [];
  const sprites = new Map();

  function sprite(style, colour) {
    const key = `${style}|${colour.join(',')}|${DPR}`;
    let entry = sprites.get(key);
    if (entry) return entry;
    const spec = STYLES[style];
    const pad = 2;
    const make = (lit) => {
      const c = document.createElement('canvas');
      c.width = Math.ceil((spec.w + pad * 2) * DPR);
      c.height = Math.ceil((spec.h + pad * 2) * DPR);
      const g = c.getContext('2d');
      g.scale(DPR, DPR);
      g.translate(pad, pad);
      const w = spec.w, h = spec.h, cx = w / 2;
      // Socket.
      const sw = style === 'globe' ? w * 0.4 : w * 0.56;
      const sh = style === 'globe' ? h * 0.26 : h * 0.26;
      g.fillStyle = '#10422a';
      g.beginPath();
      if (g.roundRect) g.roundRect(cx - sw / 2, 0, sw, sh, 1.6); else g.rect(cx - sw / 2, 0, sw, sh);
      g.fill();
      g.fillStyle = 'rgba(255,255,255,0.12)';
      g.fillRect(cx - sw / 2, sh * 0.3, sw, 1);
      g.fillRect(cx - sw / 2, sh * 0.62, sw, 1);
      // Glass.
      const top = sh * 0.82;
      g.beginPath();
      let hotY;
      if (style === 'globe') {
        const r = w * 0.48;
        hotY = h - r - 0.5;
        g.arc(cx, hotY, r, 0, Math.PI * 2);
      } else {
        hotY = top + (h - top) * 0.36;
        g.moveTo(cx, top);
        g.bezierCurveTo(cx + w * 0.66, top, cx + w * 0.52, h * 0.66, cx, h);
        g.bezierCurveTo(cx - w * 0.52, h * 0.66, cx - w * 0.66, top, cx, top);
      }
      const [r, gr, b] = colour;
      const grad = g.createRadialGradient(cx, hotY, 0, cx, hotY, h * 0.62);
      if (lit) {
        grad.addColorStop(0, 'rgb(255,250,236)');
        grad.addColorStop(0.3, `rgb(${Math.round(r + (255 - r) * 0.4)},${Math.round(gr + (255 - gr) * 0.4)},${Math.round(b + (255 - b) * 0.4)})`);
        grad.addColorStop(1, `rgb(${r},${gr},${b})`);
      } else {
        grad.addColorStop(0, `rgb(${Math.round(r * 0.55)},${Math.round(gr * 0.55)},${Math.round(b * 0.55)})`);
        grad.addColorStop(1, `rgb(${Math.round(r * 0.3 + 8)},${Math.round(gr * 0.3 + 8)},${Math.round(b * 0.3 + 10)})`);
      }
      g.fillStyle = grad;
      g.fill();
      // One specular streak, so a dark bulb still reads as glass.
      g.fillStyle = `rgba(255,255,255,${lit ? 0.6 : 0.4})`;
      g.beginPath();
      g.ellipse(cx - w * 0.2, hotY - h * 0.1, w * 0.08, h * 0.12, -0.3, 0, Math.PI * 2);
      g.fill();
      return c;
    };
    const glow = document.createElement('canvas');
    glow.width = glow.height = 96;
    const gg = glow.getContext('2d');
    const halo = gg.createRadialGradient(48, 48, 0, 48, 48, 48);
    halo.addColorStop(0, `rgba(${colour[0]},${colour[1]},${colour[2]},0.55)`);
    halo.addColorStop(0.35, `rgba(${colour[0]},${colour[1]},${colour[2]},0.2)`);
    halo.addColorStop(1, `rgba(${colour[0]},${colour[1]},${colour[2]},0)`);
    gg.fillStyle = halo;
    gg.fillRect(0, 0, 96, 96);
    entry = { unlit: make(false), lit: make(true), glow, pad };
    sprites.set(key, entry);
    return entry;
  }

  function hangLights() {
    const spec = STYLES[state.style];
    const y0 = 9, inset = 14;
    const length = W - inset * 2;
    bulbs = [];
    wire = [];
    if (length < spec.pitch * 2) return;
    const scallops = Math.max(Math.floor(length / spec.pitch / spec.per), 1);
    const span = length / scallops;
    for (let s = 0; s < scallops; s++) {
      for (let k = (s === 0 ? 0 : 1); k <= 10; k++) {
        const t = k / 10;
        wire.push([inset + (s + t) * span, y0 + spec.sag * 4 * t * (1 - t)]);
      }
      for (let k = 0; k < spec.per; k++) {
        const t = (k + 0.5) / spec.per;
        bulbs.push({
          x: inset + (s + t) * span,
          y: y0 + spec.sag * 4 * t * (1 - t),
          tilt: rand(-0.16, 0.16),
          seed: Math.random(),
        });
      }
    }
  }

  function lightLevel(i, n, slot, slots, t, seed) {
    switch (state.pattern) {
      case 'twinkle':
        return 0.28 + 0.72 * smooth(0.25, 0.65, noise(t * 0.9 + seed * 100, i));
      case 'chase': {
        let p = i / 4 - t * 0.9;
        p -= Math.floor(p);
        return 0.12 + 0.88 * smooth(0, 0.1, p) * (1 - smooth(0.26, 0.48, p));
      }
      case 'wave':
        return 0.12 + 0.88 * Math.pow(0.5 + 0.5 * Math.sin(i * 0.42 - t * 2.6), 1.6);
      default:
        return 1;
    }
  }

  function drawLights(t) {
    if (!bulbs.length) return;
    const spec = STYLES[state.style];
    const colours = PALETTES[state.palette];
    ctx.strokeStyle = 'rgba(12, 58, 34, 0.95)';
    ctx.lineWidth = 1.5;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    wire.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
    ctx.stroke();

    const lean = clamp(wind / 420, -0.4, 0.4);
    const time = t * 1.3;
    const n = bulbs.length;
    const levels = new Array(n);
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < n; i++) {
      const b = bulbs[i];
      const slot = i % colours.length;
      const level = lightLevel(i, n, slot, colours.length, time, b.seed);
      levels[i] = level;
      const s = sprite(state.style, colours[slot]);
      const size = Math.max(spec.w * 5.2, 46) * (0.75 + 0.25 * level);
      ctx.globalAlpha = level * 0.85;
      ctx.drawImage(s.glow, b.x - size / 2, b.y + spec.h * 0.55 - size / 2, size, size);
    }
    ctx.globalCompositeOperation = 'source-over';
    for (let i = 0; i < n; i++) {
      const b = bulbs[i];
      const s = sprite(state.style, colours[i % colours.length]);
      const angle = b.tilt + Math.sin(t * 1.35 + b.seed * 6.283) * 0.045 - lean * (0.55 + 0.45 * b.seed);
      ctx.save();
      ctx.translate(b.x, b.y - 1);
      ctx.rotate(angle);
      const w = spec.w + s.pad * 2, h = spec.h + s.pad * 2;
      ctx.globalAlpha = 1;
      ctx.drawImage(s.unlit, -w / 2, -s.pad, w, h);
      ctx.globalAlpha = clamp(levels[i], 0, 1);
      ctx.drawImage(s.lit, -w / 2, -s.pad, w, h);
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  }

  // ---------- Snow piles ----------

  const CELL = 3;

  class Pile {
    constructor(x0, width, y, maxHeight, tapered) {
      this.x0 = x0;
      this.y = y;
      this.max = maxHeight;
      this.tapered = tapered;
      this.seed = (Math.random() * 1e6) | 0;
      this.h = new Float32Array(Math.max(Math.ceil(width / CELL), 1));
      this.right = x0 + width;
    }
    limit(i) {
      let cap = this.max * (0.58 + 0.30 * noise(i * 0.022, this.seed) + 0.12 * noise(i * 0.075, this.seed + 5));
      if (this.tapered) cap *= smooth(1, 9, Math.min(i, this.h.length - 1 - i));
      return cap;
    }
    heightAt(x) {
      const f = (x - this.x0) / CELL - 0.5;
      const i = Math.floor(f), n = this.h.length;
      if (i < -1 || i >= n) return 0;
      const a = this.h[Math.max(i, 0)], b = this.h[Math.min(i + 1, n - 1)];
      return a + (b - a) * (f - i);
    }
    deposit(x, amount, force) {
      const i = Math.floor((x - this.x0) / CELL), n = this.h.length;
      if (i < 0 || i >= n) return false;
      if (!force) {
        const cap = this.limit(i);
        if (cap <= 0.3 || this.h[i] >= cap) return false;
      }
      const rise = amount / CELL, last = n - 1;
      this.h[i] += rise * 0.30;
      this.h[Math.max(i - 1, 0)] += rise * 0.25;
      this.h[Math.min(i + 1, last)] += rise * 0.25;
      this.h[Math.max(i - 2, 0)] += rise * 0.10;
      this.h[Math.min(i + 2, last)] += rise * 0.10;
      return true;
    }
    relax() {
      const step = 0.85 * CELL, h = this.h;
      for (let i = 0; i < h.length - 1; i++) {
        const d = h[i] - h[i + 1];
        if (d > step) { const f = (d - step) * 0.25; h[i] -= f; h[i + 1] += f; }
        else if (d < -step) { const f = (-d - step) * 0.25; h[i] += f; h[i + 1] -= f; }
      }
    }
    shed(vx, vy) {
      const h = this.h, stride = Math.max(Math.floor(h.length / 70), 2);
      for (let i = 0; i < h.length; i += stride) {
        let area = 0, peak = 0;
        for (let j = i; j < Math.min(i + stride, h.length); j++) { area += h[j] * CELL; peak = Math.max(peak, h[j]); }
        if (area > 1.5) addClump(this.x0 + (i + stride / 2) * CELL, this.y - peak / 2, vx, vy, area);
      }
      h.fill(0);
    }
    draw(lo, hi) {
      const h = this.h, n = h.length;
      const first = Math.max(Math.floor((lo - this.x0) / CELL), 0);
      const last = Math.min(Math.ceil((hi - this.x0) / CELL), n - 1);
      if (last <= first) return;
      const base = this.y + 0.75;
      let any = false;
      ctx.beginPath();
      ctx.moveTo(clamp(this.x0 + (first + 0.5) * CELL, lo, hi), base);
      for (let i = first; i <= last; i++) {
        const v = (h[Math.max(i - 2, 0)] + h[Math.min(i + 2, n - 1)] + 4 * (h[Math.max(i - 1, 0)] + h[Math.min(i + 1, n - 1)]) + 6 * h[i]) / 16;
        if (v > 0.2) any = true;
        ctx.lineTo(clamp(this.x0 + (i + 0.5) * CELL, lo, hi), base - v);
      }
      ctx.lineTo(clamp(this.x0 + (last + 0.5) * CELL, lo, hi), base);
      ctx.closePath();
      if (!any) return;
      const shade = ctx.createLinearGradient(0, base - Math.max(this.max, 6), 0, base);
      shade.addColorStop(0, '#ffffff');
      shade.addColorStop(1, '#c9dcf3');
      ctx.fillStyle = shade;
      ctx.fill();
    }
  }

  const piles = new Map();
  let ground = null;
  let ledges = [];
  let windowRects = [];
  let lastPointer = { vx: 0, vy: 0 };
  const snowTargets = () => Array.from(hero.querySelectorAll('[data-snow]'));

  // Works out where each marked element is, sheds piles whose element moved,
  // and finds which parts of each top edge are not covered by something in front.
  function syncLedges() {
    const origin = canvas.getBoundingClientRect();
    const items = snowTargets().map((el) => {
      const r = el.getBoundingClientRect();
      return {
        el, left: r.left - origin.left, right: r.right - origin.left,
        top: r.top - origin.top, bottom: r.bottom - origin.top,
        z: Number(el.style.zIndex || 0), window: el.hasAttribute('data-drag'),
      };
    }).filter((item) => item.right - item.left > 40 && item.top > 30);

    windowRects = items.filter((item) => item.window);
    ledges = [];
    for (const item of items) {
      let pile = piles.get(item.el);
      const max = item.window ? 15 : 10;
      if (!pile) {
        pile = new Pile(item.left, item.right - item.left, item.top, max, true);
        piles.set(item.el, pile);
      } else if (Math.abs(pile.y - item.top) > 1.2 || Math.abs(pile.x0 - item.left) > 1.2
                 || Math.abs(pile.right - item.right) > 1.2) {
        const dragging = item.el.classList.contains('dragging');
        pile.shed(dragging ? lastPointer.vx * 0.3 : 0, dragging ? lastPointer.vy * 0.3 : 0);
        const fresh = new Pile(item.left, item.right - item.left, item.top, max, true);
        piles.set(item.el, fresh);
        pile = fresh;
      }
      let spans = [[Math.max(item.left, 0), Math.min(item.right, W)]];
      for (const front of items) {
        if (front === item || front.z <= item.z || !front.window) continue;
        if (!(front.top <= item.top - 3 && front.bottom >= item.top)) continue;
        const next = [];
        for (const [lo, hi] of spans) {
          if (front.right <= lo || front.left >= hi) { next.push([lo, hi]); continue; }
          if (front.left > lo) next.push([lo, front.left]);
          if (front.right < hi) next.push([front.right, hi]);
        }
        spans = next;
      }
      for (const [lo, hi] of spans) if (hi - lo >= 20) ledges.push({ lo, hi, y: item.top, pile });
    }
  }

  function hitLedge(x, y0, y1) {
    for (const ledge of ledges) {
      if (x < ledge.lo || x >= ledge.hi || ledge.y < y0 - 1) continue;
      const surface = ledge.y - ledge.pile.heightAt(x);
      if (y0 <= surface && y1 >= surface) return ledge;
    }
    return null;
  }

  // ---------- Flakes ----------

  let flakes = [];
  let clumps = [];
  let wind = 0;

  function makeFlake(anywhere) {
    const roll = Math.random();
    const f = { layer: 0, lands: false, r: 0, alpha: 0, fall: 0 };
    if (roll < 0.40) { f.r = rand(0.8, 1.5); f.alpha = rand(0.45, 0.65); f.fall = rand(26, 44); }
    else if (roll < 0.74) { f.layer = 1; f.r = rand(1.3, 2.3); f.alpha = rand(0.65, 0.85); f.fall = rand(46, 72); f.lands = Math.random() < 0.5; }
    else if (roll < 0.975) { f.layer = 2; f.r = rand(2.0, 3.6); f.alpha = rand(0.82, 0.97); f.fall = rand(74, 118); f.lands = true; }
    else { f.layer = 3; f.r = rand(7, 12); f.alpha = rand(0.14, 0.26); f.fall = rand(150, 210); }
    f.x = rand(-60, W + 60);
    f.y = anywhere ? rand(-40, H) : rand(-90, -8);
    f.vx = 0;
    f.vy = f.fall;
    f.phase = rand(0, 6.283);
    f.sway = rand(0.5, 1.6);
    f.swing = rand(6, 22) * (f.layer === 0 ? 0.6 : 1);
    f.amount = f.r * f.r * 2.4;
    return f;
  }

  function addClump(x, y, vx, vy, amount) {
    if (clumps.length > 900) return;
    clumps.push({
      x: x + rand(-3, 3), y: y + rand(-2, 2), vx: vx + rand(-26, 26), vy: vy + rand(-30, 40),
      r: clamp(Math.sqrt(amount) * 0.62, 2.2, 7), amount,
    });
  }

  function targetCount() {
    if (state.snow <= 0.01) return 0;
    const area = clamp((W * H) / (1440 * 900), 0.25, 2.6);
    return Math.round((50 + 900 * Math.pow(state.snow, 1.6)) * area);
  }

  function stepSnow(dt, t) {
    const target = targetCount();
    if (flakes.length < target) {
      const empty = flakes.length === 0;
      const add = empty ? target : Math.min(target - flakes.length, Math.max(target / 90, 4));
      for (let i = 0; i < add; i++) flakes.push(makeFlake(empty));
    }
    wind = (noise(t * 0.045, 3) * 2 - 1) * 60 + (noise(t * 0.33, 9) * 2 - 1) * 16;
    const ease = Math.min(dt * 2.6, 1);
    for (let i = 0; i < flakes.length; i++) {
      const f = flakes[i];
      const layerWind = f.layer === 0 ? 0.55 : f.layer === 1 ? 0.8 : f.layer === 2 ? 1 : 1.35;
      f.vx += (wind * layerWind + Math.sin(f.phase + t * f.sway) * f.swing - f.vx) * ease;
      f.vy += (f.fall - f.vy) * ease;
      const y0 = f.y;
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      let gone = false;
      if (f.lands) {
        const ledge = hitLedge(f.x, y0, f.y);
        if (ledge && ledge.pile.deposit(f.x, f.amount)) gone = true;
      }
      if (!gone && f.layer !== 0 && f.layer !== 3 && ground && f.y >= H - ground.heightAt(f.x)) {
        ground.deposit(f.x, f.amount * 0.8);
        gone = true;
      }
      if (f.y > H + 20) gone = true;
      if (f.x < -70) f.x += W + 130; else if (f.x > W + 70) f.x -= W + 130;
      if (gone) {
        if (flakes.length > target) { flakes[i] = flakes[flakes.length - 1]; flakes.pop(); i--; }
        else flakes[i] = makeFlake(false);
      }
    }
    for (let i = 0; i < clumps.length; i++) {
      const c = clumps[i];
      c.vy = Math.min(c.vy + 980 * dt, 640);
      c.vx += (wind * 0.4 - c.vx) * Math.min(dt * 1.2, 1);
      const y0 = c.y;
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      let gone = false;
      const ledge = c.vy > 0 ? hitLedge(c.x, y0, c.y) : null;
      if (ledge) { ledge.pile.deposit(c.x, c.amount * 0.9, ledge.pile.heightAt(c.x) < ledge.pile.max * 1.25); gone = true; }
      else if (ground && c.y >= H - ground.heightAt(c.x)) { ground.deposit(c.x, c.amount * 0.9, ground.heightAt(c.x) < ground.max * 1.25); gone = true; }
      else if (c.y > H + 20) gone = true;
      if (gone) { clumps[i] = clumps[clumps.length - 1]; clumps.pop(); i--; }
    }
    for (const pile of piles.values()) pile.relax();
    if (ground) ground.relax();
  }

  // A soft disc for the few big out-of-focus flakes nearest the viewer.
  const blur = document.createElement('canvas');
  blur.width = blur.height = 64;
  {
    const g = blur.getContext('2d');
    const soft = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    soft.addColorStop(0, 'rgba(255,255,255,1)');
    soft.addColorStop(0.45, 'rgba(255,255,255,0.55)');
    soft.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = soft;
    g.fillRect(0, 0, 64, 64);
  }

  function drawFlakes(front) {
    ctx.fillStyle = '#fff';
    for (const f of flakes) {
      if ((f.layer === 0) === front) continue;
      if (f.layer === 3) {
        ctx.globalAlpha = f.alpha;
        ctx.drawImage(blur, f.x - f.r * 1.3, f.y - f.r * 1.3, f.r * 2.6, f.r * 2.6);
        continue;
      }
      if (!front) {
        // Distant snow stays behind the windows.
        let hidden = false;
        for (const r of windowRects) {
          if (f.x > r.left && f.x < r.right && f.y > r.top && f.y < r.bottom) { hidden = true; break; }
        }
        if (hidden) continue;
      }
      ctx.globalAlpha = f.alpha;
      ctx.beginPath();
      ctx.arc(f.x, f.y, f.r, 0, 6.283);
      ctx.fill();
    }
    if (front) {
      ctx.globalAlpha = 0.96;
      for (const c of clumps) {
        ctx.beginPath();
        ctx.arc(c.x, c.y, c.r, 0, 6.283);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  // ---------- Santa ----------

  const art = {};
  for (const name of ['sleigh', 'reindeerStride', 'reindeerGather']) {
    const image = new Image();
    image.src = `assets/${name}.png`;
    art[name] = image;
  }
  let santa = null;
  let sparks = [];
  let nextSanta = 7;

  function sendSanta() {
    if (santa || !art.sleigh.complete || !art.sleigh.naturalWidth) return;
    const scale = W < 700 ? 0.62 : 0.95;
    const train = (5 * 50 + 150) * scale;
    const speed = rand(240, 300) * (W < 700 ? 0.7 : 1);
    santa = {
      scale, elapsed: 0, start: -90, end: W + 90 + train,
      baseY: H * rand(0.22, 0.34), amp: H * rand(0.05, 0.09),
      duration: (W + 180 + train) / speed,
    };
  }

  function santaY(x) {
    const u = Math.abs(x - santa.start) / Math.max(santa.end - santa.start, 1);
    return santa.baseY - santa.amp * Math.sin(u * Math.PI) + santa.amp * 0.22 * Math.sin(u * Math.PI * 5);
  }

  function stepSanta(dt) {
    if (santa) {
      santa.elapsed += dt;
      if (santa.elapsed >= santa.duration) santa = null;
      else {
        const s = santa.scale;
        const lead = santa.start + (santa.end - santa.start) * (santa.elapsed / santa.duration);
        const sx = lead - (5 * 50 + 70) * s - 46 * s;
        const sy = santaY(lead - (5 * 50 + 70) * s) + 14 * s;
        let count = dt * 70;
        while (count > 0 && sparks.length < 600) {
          if (count >= 1 || Math.random() < count) {
            const life = rand(0.7, 1.8);
            sparks.push({
              x: sx + rand(-10, 10), y: sy + rand(-14, 14), vx: -rand(20, 90), vy: rand(-20, 34),
              size: rand(1.2, 3), life, max: life, gold: Math.random() < 0.7, tw: rand(0, 6.283),
            });
          }
          count -= 1;
        }
      }
    }
    for (let i = 0; i < sparks.length; i++) {
      const p = sparks[i];
      p.life -= dt;
      if (p.life <= 0) { sparks[i] = sparks[sparks.length - 1]; sparks.pop(); i--; continue; }
      p.vx *= Math.max(1 - 0.9 * dt, 0);
      p.vy = p.vy * Math.max(1 - 0.9 * dt, 0) + 46 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
  }

  function drawSanta(t) {
    if (santa) {
      const s = santa.scale;
      const lead = santa.start + (santa.end - santa.start) * (santa.elapsed / santa.duration);
      const deer = [];
      for (let k = 0; k < 5; k++) {
        const x = lead - k * 50 * s;
        deer.push({ x, y: santaY(x) + Math.sin(santa.elapsed * 6.2 + k * 1.1) * 3.5 * s, k });
      }
      const sleighX = lead - (5 * 50 + 62) * s;
      const sleighY = santaY(sleighX) + Math.sin(santa.elapsed * 3.1) * 3 * s;
      // Reins, under the sprites.
      ctx.strokeStyle = 'rgba(107, 64, 31, 0.95)';
      ctx.lineWidth = 1.1 * s;
      ctx.beginPath();
      ctx.moveTo(sleighX + (86 - 59) * s, sleighY + (40.8 - 40) * s);
      for (let k = 4; k >= 0; k--) ctx.lineTo(deer[k].x + (30 - 35) * s, deer[k].y + (24 - 29) * s);
      ctx.stroke();
      for (let k = 4; k >= 0; k--) {
        const stride = Math.floor(santa.elapsed * 7 + k * 0.5) % 2 === 0;
        const image = stride ? art.reindeerStride : art.reindeerGather;
        ctx.drawImage(image, deer[k].x - 35 * s, deer[k].y - 29 * s, 70 * s, 58 * s);
      }
      ctx.drawImage(art.sleigh, sleighX - 59 * s, sleighY - 40 * s, 118 * s, 80 * s);
      // The lead reindeer's nose glows.
      const nx = deer[0].x + (64.2 - 35) * s, ny = deer[0].y + (15.3 - 29) * s;
      const glow = ctx.createRadialGradient(nx, ny, 0, nx, ny, 22 * s);
      glow.addColorStop(0, 'rgba(255,40,30,0.9)');
      glow.addColorStop(0.25, 'rgba(255,40,30,0.35)');
      glow.addColorStop(1, 'rgba(255,40,30,0)');
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = glow;
      ctx.fillRect(nx - 22 * s, ny - 22 * s, 44 * s, 44 * s);
      ctx.globalCompositeOperation = 'source-over';
    }
    if (sparks.length) {
      ctx.globalCompositeOperation = 'lighter';
      for (const p of sparks) {
        const age = p.life / p.max;
        ctx.globalAlpha = Math.min(age * 2.2, 1) * (0.72 + 0.28 * Math.sin(t * 17 + p.tw));
        ctx.fillStyle = p.gold ? '#ffd15c' : '#fff7e6';
        const r = p.size * (0.6 + 0.4 * age);
        ctx.fillRect(p.x - r * 2.2, p.y - 0.5, r * 4.4, 1);
        ctx.fillRect(p.x - 0.5, p.y - r * 2.2, 1, r * 4.4);
        ctx.beginPath();
        ctx.arc(p.x, p.y, r * 0.7, 0, 6.283);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = 'source-over';
    }
  }

  // ---------- Frame ----------

  function render(t) {
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.clearRect(0, 0, W, H);
    drawFlakes(false);
    for (const ledge of ledges) ledge.pile.draw(ledge.lo, ledge.hi);
    if (ground) ground.draw(0, W);
    drawFlakes(true);
    drawSanta(t);
    drawLights(t);
  }

  let raf = 0;
  let previous = 0;
  let visible = true;

  function frame(stamp) {
    raf = 0;
    const dt = clamp((stamp - previous) / 1000, 0, 1 / 20);
    previous = stamp;
    now += dt;
    syncLedges();
    stepSnow(dt, now);
    stepSanta(dt);
    if (!santa && now >= nextSanta) {
      sendSanta();
      nextSanta = now + rand(45, 75);
    }
    render(now);
    schedule();
  }

  function schedule() {
    if (!raf && state.playing && visible && !document.hidden) {
      raf = requestAnimationFrame((stamp) => {
        if (!previous || stamp - previous > 400) previous = stamp - 16;
        frame(stamp);
      });
    }
  }

  // A settled, motionless picture for people who have asked for less motion.
  function renderStill() {
    syncLedges();
    for (let i = 0; i < 1500; i++) {
      now += 1 / 30;
      stepSnow(1 / 30, now);
    }
    const pattern = state.pattern;
    state.pattern = 'steady';
    render(now);
    state.pattern = pattern;
  }

  function resize() {
    const rect = hero.getBoundingClientRect();
    const width = Math.round(rect.width), height = Math.round(rect.height);
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (width === W && height === H && dpr === DPR) return;
    W = width; H = height; DPR = dpr;
    canvas.width = Math.round(W * DPR);
    canvas.height = Math.round(H * DPR);
    ground = new Pile(0, W, H, 24, false);
    piles.clear();
    flakes = [];
    clumps = [];
    hangLights();
    if (state.playing) schedule(); else renderStill();
  }

  // ---------- Controls ----------

  const motionButton = hero.querySelector('[data-action="motion"]');
  function updateMotionButton() {
    if (!motionButton) return;
    motionButton.hidden = false;
    motionButton.textContent = state.playing ? 'Pause' : 'Play animation';
    motionButton.setAttribute('aria-pressed', String(!state.playing));
  }

  hero.querySelectorAll('.seg').forEach((group) => {
    group.addEventListener('click', (event) => {
      const button = event.target.closest('button');
      if (!button) return;
      group.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', String(b === button)));
      state[group.dataset.control] = button.dataset.value;
      if (group.dataset.control === 'style') hangLights();
      if (!state.playing) renderStill();
    });
  });
  const snowSlider = hero.querySelector('[data-control="snow"]');
  if (snowSlider) {
    snowSlider.addEventListener('input', () => {
      state.snow = Number(snowSlider.value) / 100;
      if (!state.playing) { flakes = []; renderStill(); }
    });
  }
  hero.querySelector('[data-action="santa"]')?.addEventListener('click', () => {
    if (!state.playing) { state.playing = true; updateMotionButton(); }
    sendSanta();
    nextSanta = now + rand(45, 75);
    schedule();
  });
  motionButton?.addEventListener('click', () => {
    state.playing = !state.playing;
    updateMotionButton();
    if (state.playing) schedule(); else { cancelAnimationFrame(raf); raf = 0; }
  });

  // Dragging the pretend windows.
  let topZ = 10;
  hero.querySelectorAll('[data-drag]').forEach((win, index) => {
    win.style.zIndex = String(index + 1);
    let drag = null;
    win.addEventListener('pointerdown', (event) => {
      if (event.target.closest('button, input, a, label')) return;
      if (event.button !== undefined && event.button !== 0) return;
      const [x = 0, y = 0] = (win.dataset.offset || '0,0').split(',').map(Number);
      drag = { id: event.pointerId, sx: event.clientX, sy: event.clientY, x, y, px: event.clientX, py: event.clientY, t: event.timeStamp };
      win.setPointerCapture(event.pointerId);
      win.classList.add('dragging');
      win.style.zIndex = String(++topZ);
    });
    win.addEventListener('pointermove', (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      const dt = Math.max((event.timeStamp - drag.t) / 1000, 0.001);
      lastPointer = {
        vx: clamp((event.clientX - drag.px) / dt, -1400, 1400),
        vy: clamp((event.clientY - drag.py) / dt, -900, 1400),
      };
      drag.px = event.clientX; drag.py = event.clientY; drag.t = event.timeStamp;
      const x = drag.x + event.clientX - drag.sx, y = drag.y + event.clientY - drag.sy;
      win.dataset.offset = `${x},${y}`;
      win.style.transform = `translate(${x}px, ${y}px)`;
      if (!state.playing) { syncLedges(); render(now); }
    });
    const end = (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      drag = null;
      win.classList.remove('dragging');
    };
    win.addEventListener('pointerup', end);
    win.addEventListener('pointercancel', end);
  });

  // ---------- Page chrome ----------

  const formatSize = (bytes) => `${(bytes / 1048576).toFixed(1)} MB`;
  fetch('version.json', { cache: 'no-store' })
    .then((response) => (response.ok ? response.json() : null))
    .then((info) => {
      if (!info || !info.version) return;
      document.querySelectorAll('[data-version]').forEach((el) => { el.textContent = `Free · Version ${info.version}`; });
      if (info.size) document.querySelectorAll('[data-size]').forEach((el) => { el.textContent = `${formatSize(info.size)} · Signed and notarized`; });
      if (info.sha256) {
        document.querySelectorAll('[data-hash]').forEach((el) => { el.textContent = `SHA-256 ${info.sha256}`; el.hidden = false; });
      }
    })
    .catch(() => {});

  const onMac = /Macintosh|Mac OS X/.test(navigator.userAgent) && navigator.maxTouchPoints < 2;
  if (!onMac) {
    const note = document.querySelector('.phone-note');
    if (note) {
      note.hidden = false;
      note.querySelector('[data-share]')?.addEventListener('click', async (event) => {
        const url = 'https://chonkbase.net/griswold/';
        try {
          if (navigator.share) await navigator.share({ title: 'Griswold', text: 'Snow and Christmas lights for your Mac', url });
          else { await navigator.clipboard.writeText(url); event.target.textContent = 'Link copied'; }
        } catch (_) { /* cancelled */ }
      });
    }
  }

  // ---------- Start ----------

  if ('IntersectionObserver' in window) {
    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      schedule();
    }).observe(hero);
  }
  document.addEventListener('visibilitychange', schedule);
  if ('ResizeObserver' in window) new ResizeObserver(resize).observe(hero);
  window.addEventListener('resize', resize);
  reducedMotion.addEventListener?.('change', () => {
    state.playing = !reducedMotion.matches;
    updateMotionButton();
    if (state.playing) schedule(); else renderStill();
  });
  updateMotionButton();
  resize();
})();
