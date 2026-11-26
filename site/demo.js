// A small port of what the app does, drawn on one canvas fixed over the page.
// Snow falls across the whole page and lands on anything marked data-snow;
// drag one of the pretend windows and its snow falls off. The panel in the
// header is a working copy of the app's menu bar popover.
(() => {
  'use strict';

  const canvas = document.getElementById('sky');
  if (!canvas || !canvas.getContext) return;
  const ctx = canvas.getContext('2d');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  const state = {
    enabled: true, snowOn: true, lightsOn: true,
    style: 'c9', palette: 'classic', pattern: 'twinkle',
    snow: 0.45, depth: 15, playing: !reducedMotion.matches,
  };
  let W = 0, H = 0, SCALE = 1;
  let now = 0;
  let scrollY = window.scrollY;

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
  let lightsFade = 1;
  const sprites = new Map();

  function sprite(style, colour) {
    const key = `${style}|${colour.join(',')}|${SCALE}`;
    let entry = sprites.get(key);
    if (entry) return entry;
    const spec = STYLES[style];
    const pad = 2;
    const make = (lit) => {
      const c = document.createElement('canvas');
      c.width = Math.ceil((spec.w + pad * 2) * SCALE);
      c.height = Math.ceil((spec.h + pad * 2) * SCALE);
      const g = c.getContext('2d');
      g.scale(SCALE, SCALE);
      g.translate(pad, pad);
      const w = spec.w, h = spec.h, cx = w / 2;
      const sw = style === 'globe' ? w * 0.4 : w * 0.56;
      const sh = h * 0.26;
      g.fillStyle = '#10422a';
      g.beginPath();
      if (g.roundRect) g.roundRect(cx - sw / 2, 0, sw, sh, 1.6); else g.rect(cx - sw / 2, 0, sw, sh);
      g.fill();
      g.fillStyle = 'rgba(255,255,255,0.12)';
      g.fillRect(cx - sw / 2, sh * 0.3, sw, 1);
      g.fillRect(cx - sw / 2, sh * 0.62, sw, 1);
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
    const inset = 14;
    const length = W - inset * 2;
    bulbs = [];
    wire = [];
    if (length < spec.pitch * 2) return;
    const scallops = Math.max(Math.floor(length / spec.pitch / spec.per), 1);
    const span = length / scallops;
    for (let s = 0; s < scallops; s++) {
      for (let k = (s === 0 ? 0 : 1); k <= 10; k++) {
        const t = k / 10;
        wire.push([inset + (s + t) * span, spec.sag * 4 * t * (1 - t)]);
      }
      for (let k = 0; k < spec.per; k++) {
        const t = (k + 0.5) / spec.per;
        bulbs.push({ x: inset + (s + t) * span, y: spec.sag * 4 * t * (1 - t), tilt: rand(-0.16, 0.16), seed: Math.random() });
      }
    }
  }

  function lightLevel(i, t, seed) {
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

  // The string hangs along the top of the page and scrolls away with it.
  function drawLights(t, still) {
    const top = 9 - scrollY;
    if (!bulbs.length || top < -70 || lightsFade < 0.01) return;
    const spec = STYLES[state.style];
    const colours = PALETTES[state.palette];
    ctx.globalAlpha = lightsFade;
    ctx.strokeStyle = 'rgba(12, 58, 34, 0.95)';
    ctx.lineWidth = 1.5;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    wire.forEach(([x, y], i) => (i ? ctx.lineTo(x, top + y) : ctx.moveTo(x, top + y)));
    ctx.stroke();

    const lean = clamp(wind / 420, -0.4, 0.4);
    const time = t * 1.3;
    const levels = new Array(bulbs.length);
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < bulbs.length; i++) {
      const b = bulbs[i];
      const level = still ? 1 : lightLevel(i, time, b.seed);
      levels[i] = level;
      const s = sprite(state.style, colours[i % colours.length]);
      const size = Math.max(spec.w * 5.2, 46) * (0.75 + 0.25 * level);
      ctx.globalAlpha = level * 0.85 * lightsFade;
      ctx.drawImage(s.glow, b.x - size / 2, top + b.y + spec.h * 0.55 - size / 2, size, size);
    }
    ctx.globalCompositeOperation = 'source-over';
    for (let i = 0; i < bulbs.length; i++) {
      const b = bulbs[i];
      const s = sprite(state.style, colours[i % colours.length]);
      const angle = b.tilt + Math.sin(t * 1.35 + b.seed * 6.283) * 0.045 - lean * (0.55 + 0.45 * b.seed);
      ctx.save();
      ctx.translate(b.x, top + b.y - 1);
      ctx.rotate(angle);
      const w = spec.w + s.pad * 2, h = spec.h + s.pad * 2;
      ctx.globalAlpha = lightsFade;
      ctx.drawImage(s.unlit, -w / 2, -s.pad, w, h);
      ctx.globalAlpha = clamp(levels[i], 0, 1) * lightsFade;
      ctx.drawImage(s.lit, -w / 2, -s.pad, w, h);
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  }

  // ---------- Snow piles ----------

  const CELL = 3;

  class Pile {
    constructor(width, tapered) {
      this.x0 = 0;
      this.y = 0;
      this.max = 0;
      this.width = width;
      this.tapered = tapered;
      this.seed = (Math.random() * 1e6) | 0;
      this.h = new Float32Array(Math.max(Math.ceil(width / CELL), 1));
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
    settle(dt) {
      const step = 0.85 * CELL, h = this.h;
      for (let i = 0; i < h.length; i++) {
        // Sinks back to its limit when the depth is turned down, or to nothing when off.
        const cap = this.limit(i);
        if (h[i] > cap) h[i] = Math.max(cap, h[i] - dt * 5);
      }
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
    plow(lo, hi, leaving) {
      const h = this.h;
      const first = Math.max(Math.floor((Math.min(lo, hi) - this.x0) / CELL), 0);
      const last = Math.min(Math.ceil((Math.max(lo, hi) - this.x0) / CELL), h.length - 1);
      let removed = 0;
      for (let i = first; i <= last; i++) {
        if (h[i] > leaving) { removed += (h[i] - leaving) * CELL; h[i] = leaving; }
      }
      return removed;
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

  // Everything snow can land on. Only what is near the viewport is measured each frame.
  const targets = $$('[data-snow]');
  const nearby = new Set(targets);
  const piles = new Map();
  let ledges = [];
  let solids = [];

  function depthFor(el) {
    if (!state.enabled || !state.snowOn) return 0;
    if (el.hasAttribute('data-ground')) return state.depth * 1.7;
    if (el.classList.contains('cta')) return Math.min(state.depth, 10);
    return state.depth;
  }

  // Finds where each target is now. Piles ride along with their element (so
  // scrolling does not disturb them) and are only shed by dragging.
  function syncLedges() {
    const items = [];
    solids = [];
    for (const el of nearby) {
      const r = el.getBoundingClientRect();
      if (r.width < 40 || r.bottom < -80 || r.top > H + 80) continue;
      const item = { el, left: r.left, right: r.right, top: r.top, bottom: r.bottom, z: Number(el.style.zIndex || 0), drag: el.hasAttribute('data-drag') };
      items.push(item);
      if (el.hasAttribute('data-solid')) solids.push(item);
    }
    ledges = [];
    for (const item of items) {
      let pile = piles.get(item.el);
      const width = item.right - item.left;
      if (!pile || Math.abs(pile.width - width) > 2) {
        pile = new Pile(width, !item.el.hasAttribute('data-ground'));
        piles.set(item.el, pile);
      }
      pile.x0 = item.left;
      pile.y = item.top;
      pile.max = depthFor(item.el);
      let spans = [[Math.max(item.left, 0), Math.min(item.right, W)]];
      for (const front of items) {
        if (front === item || !front.drag || front.z <= item.z) continue;
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
      if (y0 <= surface && y1 >= surface) return { pile: ledge.pile, y: surface };
    }
    return null;
  }

  // The surface under a runner: a ledge within reach, or the bottom of the window.
  function support(x, y, tolerance) {
    const hit = hitLedge(x, y - tolerance, y + tolerance);
    if (hit) return hit;
    return Math.abs(H - 2 - y) <= tolerance ? { pile: null, y: H - 2 } : null;
  }

  function kickSnow(pile, from, to, y, vx, vy, leaving) {
    if (!pile) return;
    const removed = pile.plow(from, to, leaving);
    if (removed < 0.5) return;
    const pieces = clamp(Math.floor(removed / 14), 1, 6);
    for (let i = 0; i < pieces; i++) addClump((from + to) / 2 + rand(-6, 6), y - 3, vx + rand(-60, 60), vy - rand(20, 160), removed / pieces);
  }

  // ---------- Flakes ----------

  let flakes = [];
  let clumps = [];
  let wind = 0;

  function makeFlake(anywhere) {
    const roll = Math.random();
    const f = { layer: 0, lands: false, r: 0, alpha: 0, fall: 0 };
    if (roll < 0.42) { f.r = rand(0.8, 1.5); f.alpha = rand(0.45, 0.65); f.fall = rand(26, 44); }
    else if (roll < 0.76) { f.layer = 1; f.r = rand(1.3, 2.3); f.alpha = rand(0.65, 0.85); f.fall = rand(46, 72); f.lands = Math.random() < 0.5; }
    else if (roll < 0.985) { f.layer = 2; f.r = rand(2.0, 3.4); f.alpha = rand(0.82, 0.97); f.fall = rand(74, 118); f.lands = true; }
    else { f.layer = 3; f.r = rand(7, 12); f.alpha = rand(0.12, 0.22); f.fall = rand(150, 210); }
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
    clumps.push({ x: x + rand(-3, 3), y: y + rand(-2, 2), vx: vx + rand(-26, 26), vy: vy + rand(-30, 40), r: clamp(Math.sqrt(amount) * 0.62, 2.2, 7), amount });
  }

  function targetCount() {
    if (!state.enabled || !state.snowOn || state.snow <= 0.01) return 0;
    const area = clamp((W * H) / (1440 * 900), 0.25, 2.4);
    return Math.round((40 + 620 * Math.pow(state.snow, 1.6)) * area);
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
        const hit = hitLedge(f.x, y0, f.y);
        if (hit && hit.pile.deposit(f.x, f.amount)) gone = true;
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
      const hit = c.vy > 0 ? hitLedge(c.x, y0, c.y) : null;
      if (hit) hit.pile.deposit(c.x, c.amount * 0.9, hit.pile.heightAt(c.x) < hit.pile.max * 1.25);
      if (hit || c.y > H + 20) { clumps[i] = clumps[clumps.length - 1]; clumps.pop(); i--; }
    }
    for (const pile of piles.values()) pile.settle(dt);
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
        // Distant snow stays behind windows and pictures.
        let hidden = false;
        for (const r of solids) {
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

  // ---------- Surprises ----------

  const art = {};
  for (const name of ['sleigh', 'reindeerStride', 'reindeerGather', 'squirrelStride', 'squirrelGather', 'sled']) {
    const image = new Image();
    image.src = `assets/${name}.png`;
    art[name] = image;
  }
  const ready = (image) => image.complete && image.naturalWidth > 0;

  let sparks = [];
  function spark(x, y, vx, vy, colour, size, life, gravity, drag) {
    if (sparks.length > 900) return;
    sparks.push({ x, y, vx, vy, colour, size, life, max: life, gravity, drag, tw: rand(0, 6.283) });
  }

  let santa = null;
  let squirrel = null;
  let sled = null;
  let nextSurprise = 7;
  let lastSurprise = '';

  function sendSanta() {
    if (santa || !ready(art.sleigh)) return;
    const scale = W < 700 ? 0.62 : 0.95;
    const train = (5 * 50 + 150) * scale;
    const speed = rand(240, 300) * (W < 700 ? 0.7 : 1);
    santa = { scale, elapsed: 0, start: -90, end: W + 90 + train, baseY: H * rand(0.2, 0.32), amp: H * rand(0.05, 0.09), duration: (W + 180 + train) / speed };
  }
  const santaY = (x) => {
    const u = Math.abs(x - santa.start) / Math.max(santa.end - santa.start, 1);
    return santa.baseY - santa.amp * Math.sin(u * Math.PI) + santa.amp * 0.22 * Math.sin(u * Math.PI * 5);
  };

  function sendSquirrel() {
    if (squirrel || !ready(art.squirrelStride)) return;
    const dir = Math.random() < 0.5 ? 1 : -1;
    squirrel = {
      x: dir > 0 ? rand(20, W * 0.2) : rand(W * 0.8, W - 20), y: 30, vx: dir * 160, vy: 40, dir,
      grounded: false, age: 0, pause: 0, pauses: 2, scale: W < 700 ? 0.9 : 1.15,
    };
  }

  function sendSled() {
    if (sled || !ready(art.sled)) return;
    sled = { dir: Math.random() < 0.5 ? 1 : -1, pass: 0, wait: 0, scale: W < 700 ? 0.9 : 1.2, rot: 0 };
    beginPass(sled);
  }
  function beginPass(s) {
    const fraction = [0.2, 0.5, 1][Math.min(s.pass, 2)];
    s.grounded = fraction >= 1;
    s.x = s.dir > 0 ? -140 : W + 140;
    s.y = fraction >= 1 ? H - 2 : Math.max(70, H * fraction);
    s.vx = s.dir * rand(1300, 1650) * clamp(W / 1500, 0.6, 1.4);
    s.vy = fraction >= 1 ? 0 : -80;
    s.rot = 0;
  }

  function surprise(kind) {
    const pool = ['squirrel', 'sled', 'santa'].filter((k) => k !== lastSurprise);
    const chosen = kind || pool[Math.floor(Math.random() * pool.length)];
    lastSurprise = chosen;
    if (chosen === 'santa') sendSanta();
    else if (chosen === 'squirrel') sendSquirrel();
    else sendSled();
    nextSurprise = now + rand(28, 45);
  }

  // The leap that carries the squirrel to the near corner of the best ledge ahead.
  function squirrelLeap(s, speed) {
    let best = null;
    for (const ledge of ledges) {
      const edge = s.dir > 0 ? ledge.lo : ledge.hi;
      const dx = (edge - s.x) * s.dir;
      if (dx < 50 || dx > 470 || ledge.hi - ledge.lo < 70) continue;
      const tx = edge + s.dir * 26;
      const rise = s.y - (ledge.y - ledge.pile.heightAt(tx));
      if (rise < -24 || rise > 330) continue;
      const time = (dx + 26) / speed;
      const vy = (-rise - 0.5 * 1500 * time * time) / time;
      if (vy < -960 || vy > -140) continue;
      if (!best || rise > best.rise) best = { vy, rise };
    }
    return best;
  }

  function stepSquirrel(dt) {
    const s = squirrel;
    if (!s) return;
    s.age += dt;
    const speed = 560 * s.scale;
    if (s.pause > 0) {
      s.pause -= dt;
      const under = support(s.x, s.y, 8);
      if (under) s.y = under.y; else { s.pause = 0; s.grounded = false; }
    } else if (s.grounded) {
      const nx = s.x + s.dir * speed * dt;
      const under = support(nx, s.y, 9);
      if (under) {
        if (under.pile) kickSnow(under.pile, s.x - 4, nx + 4, under.y, -s.dir * 110, -40, Math.max(under.pile.heightAt(nx) * 0.55, 0.4));
        s.x = nx;
        s.y = under.y;
        const leap = squirrelLeap(s, speed * 0.92);
        if (leap) { s.vx = s.dir * speed * 0.92; s.vy = leap.vy; s.grounded = false; }
      } else {
        s.vx = s.dir * speed * 0.9;
        s.vy = -rand(300, 460);
        s.grounded = false;
      }
    } else {
      s.vy += 1500 * dt;
      const y0 = s.y;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      let landing = s.vy > 0 ? hitLedge(s.x, y0, s.y) : null;
      if (!landing && s.vy > 0 && s.y >= H - 2) landing = { pile: null, y: H - 2 };
      if (landing) {
        s.y = landing.y;
        s.grounded = true;
        kickSnow(landing.pile, s.x - 16, s.x + 16, landing.y, s.vx * 0.2, -90, 0.5);
        if (s.pauses > 0 && landing.pile && Math.random() < 0.45) { s.pauses--; s.pause = rand(0.45, 0.9); }
      }
    }
    if (s.x < -90 || s.x > W + 90 || s.y > H + 120 || s.age > 18) squirrel = null;
  }

  function stepSled(dt) {
    const s = sled;
    if (!s) return;
    if (s.wait > 0) {
      s.wait -= dt;
      if (s.wait <= 0) beginPass(s);
      return;
    }
    if (s.grounded) {
      const nx = s.x + s.vx * dt;
      const under = support(nx, s.y, 12);
      if (under) {
        kickSnow(under.pile, s.x - s.dir * 12, nx + s.dir * 14, under.y, s.vx * 0.22, -rand(140, 420), 0.25);
        s.x = nx;
        s.y = under.y;
        s.rot += (0 - s.rot) * Math.min(dt * 14, 1);
        for (let n = dt * 200; n > 0; n--) {
          if (n >= 1 || Math.random() < n) spark(s.x - s.dir * rand(0, 24), s.y - 2, -s.dir * rand(40, 320), -rand(20, 260), Math.random() < 0.5 ? '#ffa029' : '#ffdb6b', rand(1.2, 2.6), rand(0.2, 0.6), 520, 0.6);
        }
      } else {
        s.grounded = false;
        s.vy = -rand(160, 380);
      }
    } else {
      s.vy += 1500 * dt;
      const y0 = s.y;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.rot += (Math.atan2(s.vy, Math.abs(s.vx)) * 0.8 - s.rot) * Math.min(dt * 8, 1);
      let landing = s.vy > 0 ? hitLedge(s.x, y0, s.y) : null;
      if (!landing && s.vy > 0 && s.y >= H - 2) landing = { pile: null, y: H - 2 };
      if (landing) {
        s.y = landing.y;
        s.vy = 0;
        s.grounded = true;
        for (let n = 0; n < 22; n++) {
          const a = rand(0, 6.283), v = rand(80, 420);
          spark(s.x, s.y, Math.cos(a) * v, Math.sin(a) * v - 120, n % 3 ? '#ffa029' : '#fff', rand(1.4, 3), rand(0.3, 0.8), 520, 0.8);
        }
        kickSnow(landing.pile, s.x - 30, s.x + 30, landing.y, s.vx * 0.15, -260, 0.25);
      }
    }
    for (let n = dt * 120; n > 0; n--) {
      if (n >= 1 || Math.random() < n) {
        const hot = Math.random();
        spark(s.x - s.dir * 34 * s.scale + rand(-6, 6), s.y - 12 * s.scale + rand(-8, 8), -s.dir * rand(40, 240), rand(-90, 40),
          `rgb(255,${Math.round(90 + 140 * hot)},${Math.round(20 + 110 * hot * hot)})`, rand(2, 4.2), rand(0.22, 0.6), -60, 1.6);
      }
    }
    const passed = s.dir > 0 ? s.x > W + 180 : s.x < -180;
    if (passed || s.y > H + 200) {
      s.pass++;
      if (s.pass >= 3) { sled = null; return; }
      s.dir = -s.dir;
      s.wait = 0.5;
    }
  }

  function stepSurprises(dt) {
    if (santa) {
      santa.elapsed += dt;
      if (santa.elapsed >= santa.duration) santa = null;
      else {
        const s = santa.scale;
        const lead = santa.start + (santa.end - santa.start) * (santa.elapsed / santa.duration);
        const sx = lead - (5 * 50 + 70) * s - 46 * s;
        const sy = santaY(lead - (5 * 50 + 70) * s) + 14 * s;
        for (let n = dt * 70; n > 0; n--) {
          if (n >= 1 || Math.random() < n) spark(sx + rand(-10, 10), sy + rand(-14, 14), -rand(20, 90), rand(-20, 34), Math.random() < 0.7 ? '#ffd15c' : '#fff7e6', rand(1.2, 3), rand(0.7, 1.8), 46, 0.9);
        }
      }
    }
    stepSquirrel(dt);
    stepSled(dt);
    for (let i = 0; i < sparks.length; i++) {
      const p = sparks[i];
      p.life -= dt;
      if (p.life <= 0) { sparks[i] = sparks[sparks.length - 1]; sparks.pop(); i--; continue; }
      const keep = Math.max(1 - p.drag * dt, 0);
      p.vx *= keep;
      p.vy = p.vy * keep + p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
  }

  function drawFlipped(image, x, y, w, h, dir, rotation) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(dir, 1);
    if (rotation) ctx.rotate(rotation);
    ctx.drawImage(image, -w / 2, -h / 2, w, h);
    ctx.restore();
  }

  function drawSurprises(t) {
    if (santa) {
      const s = santa.scale;
      const lead = santa.start + (santa.end - santa.start) * (santa.elapsed / santa.duration);
      const deer = [];
      for (let k = 0; k < 5; k++) {
        const x = lead - k * 50 * s;
        deer.push({ x, y: santaY(x) + Math.sin(santa.elapsed * 6.2 + k * 1.1) * 3.5 * s });
      }
      const sleighX = lead - (5 * 50 + 62) * s;
      const sleighY = santaY(sleighX) + Math.sin(santa.elapsed * 3.1) * 3 * s;
      ctx.strokeStyle = 'rgba(107, 64, 31, 0.95)';
      ctx.lineWidth = 1.1 * s;
      ctx.beginPath();
      ctx.moveTo(sleighX + 27 * s, sleighY + 0.8 * s);
      for (let k = 4; k >= 0; k--) ctx.lineTo(deer[k].x - 5 * s, deer[k].y - 5 * s);
      ctx.stroke();
      for (let k = 4; k >= 0; k--) {
        const stride = Math.floor(santa.elapsed * 7 + k * 0.5) % 2 === 0;
        ctx.drawImage(stride ? art.reindeerStride : art.reindeerGather, deer[k].x - 35 * s, deer[k].y - 29 * s, 70 * s, 58 * s);
      }
      ctx.drawImage(art.sleigh, sleighX - 59 * s, sleighY - 40 * s, 118 * s, 80 * s);
      const nx = deer[0].x + 29.2 * s, ny = deer[0].y - 13.7 * s;
      const glow = ctx.createRadialGradient(nx, ny, 0, nx, ny, 22 * s);
      glow.addColorStop(0, 'rgba(255,40,30,0.9)');
      glow.addColorStop(0.25, 'rgba(255,40,30,0.35)');
      glow.addColorStop(1, 'rgba(255,40,30,0)');
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = glow;
      ctx.fillRect(nx - 22 * s, ny - 22 * s, 44 * s, 44 * s);
      ctx.globalCompositeOperation = 'source-over';
    }
    if (sled && sled.wait <= 0) {
      const s = sled, k = s.scale;
      // A streak of fire behind the saucer.
      const fire = ctx.createLinearGradient(s.x - s.dir * 260 * k, 0, s.x, 0);
      fire.addColorStop(0, 'rgba(255,120,20,0)');
      fire.addColorStop(1, 'rgba(255,170,60,0.75)');
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = fire;
      ctx.beginPath();
      ctx.ellipse(s.x - s.dir * 130 * k, s.y - 14 * k, 130 * k, 9 * k, 0, 0, 6.283);
      ctx.fill();
      ctx.globalCompositeOperation = 'source-over';
      drawFlipped(art.sled, s.x, s.y - 21 * k, 78 * k, 50 * k, s.dir, s.rot);
    }
    if (squirrel) {
      const s = squirrel, k = s.scale;
      const running = s.grounded && s.pause <= 0;
      const stride = running ? Math.floor(s.age * 11) % 2 === 0 : !s.grounded;
      const tilt = s.grounded ? 0 : Math.atan2(s.vy, Math.abs(s.vx)) * 0.55;
      drawFlipped(stride ? art.squirrelStride : art.squirrelGather, s.x, s.y - 16.5 * k, 62 * k, 42 * k, s.dir, tilt);
    }
    if (sparks.length) {
      ctx.globalCompositeOperation = 'lighter';
      for (const p of sparks) {
        const age = p.life / p.max;
        ctx.globalAlpha = Math.min(age * 2.2, 1) * (0.72 + 0.28 * Math.sin(t * 17 + p.tw));
        ctx.fillStyle = p.colour;
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

  function render(t, still) {
    ctx.setTransform(SCALE, 0, 0, SCALE, 0, 0);
    ctx.clearRect(0, 0, W, H);
    drawFlakes(false);
    for (const ledge of ledges) ledge.pile.draw(ledge.lo, ledge.hi);
    drawFlakes(true);
    drawSurprises(t);
    drawLights(t, still);
  }

  // The page scrolls under the snow: move everything that is in the air by the
  // same amount, so it belongs to the page rather than to the glass.
  function followScroll() {
    const y = window.scrollY;
    const dy = y - scrollY;
    scrollY = y;
    if (!dy) return;
    if (Math.abs(dy) > H) {
      for (const f of flakes) f.y = rand(-40, H);
      clumps = [];
      return;
    }
    for (const f of flakes) {
      f.y -= dy;
      if (f.y < -100) f.y += H + 110; else if (f.y > H + 10) f.y -= H + 110;
    }
    for (const c of clumps) c.y -= dy;
    for (const p of sparks) p.y -= dy;
    if (squirrel) squirrel.y -= dy;
    if (sled && !sled.grounded) sled.y -= dy;
  }

  let raf = 0;
  let previous = 0;

  function frame(stamp) {
    raf = 0;
    const dt = clamp((stamp - previous) / 1000, 0, 1 / 20);
    previous = stamp;
    now += dt;
    followScroll();
    syncLedges();
    lightsFade += ((state.enabled && state.lightsOn ? 1 : 0) - lightsFade) * Math.min(dt * 5, 1);
    stepSnow(dt, now);
    stepSurprises(dt);
    if (state.enabled && !santa && !squirrel && !sled && now >= nextSurprise) surprise();
    render(now, false);
    schedule();
  }

  function schedule() {
    if (!raf && state.playing && !document.hidden) {
      raf = requestAnimationFrame((stamp) => {
        if (!previous || stamp - previous > 400) previous = stamp - 16;
        frame(stamp);
      });
    }
  }

  // A settled, motionless picture for people who have asked for less motion.
  function renderStill() {
    scrollY = window.scrollY;
    syncLedges();
    lightsFade = state.enabled && state.lightsOn ? 1 : 0;
    for (let i = 0; i < 1500; i++) {
      now += 1 / 30;
      stepSnow(1 / 30, now);
    }
    render(now, true);
  }

  function resize() {
    const width = document.documentElement.clientWidth, height = window.innerHeight;
    // Sharp on ordinary screens, but never more pixels than the effect is worth.
    const scale = Math.max(1, Math.min(window.devicePixelRatio || 1, 2, Math.sqrt(6.5e6 / (width * height))));
    if (width === W && height === H && scale === SCALE) return;
    const widthChanged = width !== W;
    W = width; H = height; SCALE = scale;
    canvas.width = Math.round(W * SCALE);
    canvas.height = Math.round(H * SCALE);
    if (widthChanged) {
      flakes = [];
      clumps = [];
      hangLights();
    }
    if (state.playing) schedule(); else renderStill();
  }

  // ---------- The panel ----------

  const panel = $('.popover');
  const motionButton = $('[data-action="motion"]');

  function refreshPanel() {
    if (panel) panel.classList.toggle('off', !state.enabled);
    const strip = $('[data-bulbs]');
    if (strip) {
      const colours = PALETTES[state.palette];
      strip.innerHTML = '';
      for (let i = 0; i < 11; i++) {
        const bulb = document.createElement('i');
        const [r, g, b] = colours[i % colours.length];
        bulb.style.setProperty('--c', `rgb(${r},${g},${b})`);
        bulb.style.setProperty('--o', state.enabled && state.lightsOn ? '1' : '0.4');
        strip.appendChild(bulb);
      }
    }
    if (motionButton) motionButton.textContent = state.playing ? 'Pause' : 'Play';
    if (!state.playing) renderStill();
  }

  function countdown() {
    const today = new Date();
    const month = today.getMonth() + 1, day = today.getDate();
    if (month === 12 && day === 25) return 'Merry Christmas!';
    if (month === 12 && day === 24) return "It's Christmas Eve";
    if (month === 12 && day > 25) return 'Happy holidays';
    const start = new Date(today.getFullYear(), today.getMonth(), day);
    const days = Math.round((new Date(today.getFullYear(), 11, 25) - start) / 86400000);
    return days === 1 ? '1 day until Christmas' : `${days} days until Christmas`;
  }
  const countdownLabel = $('[data-countdown]');
  if (countdownLabel) countdownLabel.textContent = countdown();

  $$('input[type="checkbox"][data-control]').forEach((box) => {
    box.addEventListener('change', () => { state[box.dataset.control] = box.checked; refreshPanel(); });
  });
  $$('select[data-control]').forEach((select) => {
    select.addEventListener('change', () => {
      if (select.dataset.control === 'surprise') {
        if (!state.playing) { state.playing = true; }
        if (!state.enabled) { state.enabled = true; const master = $('[data-control="enabled"]'); if (master) master.checked = true; }
        surprise(select.value);
        select.value = '';
        refreshPanel();
        schedule();
        return;
      }
      state[select.dataset.control] = select.value;
      if (select.dataset.control === 'style') hangLights();
      refreshPanel();
    });
  });
  const slider = $('[data-control="snow"]');
  if (slider) slider.addEventListener('input', () => {
    state.snow = Number(slider.value) / 100;
    if (!state.playing) { flakes = []; renderStill(); }
  });
  $$('.seg').forEach((group) => {
    group.addEventListener('click', (event) => {
      const button = event.target.closest('button');
      if (!button) return;
      $$('button', group).forEach((b) => b.setAttribute('aria-pressed', String(b === button)));
      state.depth = Number(button.dataset.value);
      if (!state.playing) renderStill();
    });
  });
  if (motionButton) motionButton.addEventListener('click', () => {
    state.playing = !state.playing;
    if (state.playing) { refreshPanel(); schedule(); }
    else { cancelAnimationFrame(raf); raf = 0; refreshPanel(); }
  });

  // Dragging the pretend windows knocks their snow off.
  let topZ = 10;
  $$('[data-drag]').forEach((win, index) => {
    win.style.zIndex = String(index + 1);
    let drag = null;
    win.addEventListener('pointerdown', (event) => {
      if (event.target.closest('button, input, a, select, label')) return;
      if (event.button !== undefined && event.button !== 0) return;
      const [x = 0, y = 0] = (win.dataset.offset || '0,0').split(',').map(Number);
      drag = { id: event.pointerId, sx: event.clientX, sy: event.clientY, x, y, px: event.clientX, py: event.clientY, t: event.timeStamp, shed: false };
      win.setPointerCapture(event.pointerId);
      win.classList.add('dragging');
      win.style.zIndex = String(++topZ);
    });
    win.addEventListener('pointermove', (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      const dt = Math.max((event.timeStamp - drag.t) / 1000, 0.001);
      const vx = clamp((event.clientX - drag.px) / dt, -1400, 1400);
      const vy = clamp((event.clientY - drag.py) / dt, -900, 1400);
      drag.px = event.clientX; drag.py = event.clientY; drag.t = event.timeStamp;
      const x = drag.x + event.clientX - drag.sx, y = drag.y + event.clientY - drag.sy;
      if (!drag.shed && Math.hypot(event.clientX - drag.sx, event.clientY - drag.sy) > 3) {
        drag.shed = true;
        const pile = piles.get(win);
        if (pile) pile.shed(vx * 0.3, vy * 0.3);
      }
      win.dataset.offset = `${x},${y}`;
      win.style.transform = `translate(${x}px, ${y}px)`;
      if (!state.playing) { syncLedges(); render(now, true); }
    });
    const end = (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      drag = null;
      win.classList.remove('dragging');
    };
    win.addEventListener('pointerup', end);
    win.addEventListener('pointercancel', end);
  });

  // ---------- Page details ----------

  fetch('version.json', { cache: 'no-store' })
    .then((response) => (response.ok ? response.json() : null))
    .then((info) => {
      if (!info || !info.version) return;
      $$('[data-version]').forEach((el) => { el.textContent = `Free and open source · v${info.version}`; });
      if (info.size) $$('[data-size]').forEach((el) => { el.textContent = `${(info.size / 1048576).toFixed(1)} MB`; });
      if (info.sha256) $$('[data-hash]').forEach((el) => { el.textContent = `SHA-256 ${info.sha256}`; el.hidden = false; });
    })
    .catch(() => {});

  const onMac = /Macintosh|Mac OS X/.test(navigator.userAgent) && navigator.maxTouchPoints < 2;
  const note = $('.phone-note');
  if (!onMac && note) {
    note.hidden = false;
    const share = $('[data-share]', note);
    if (share) share.addEventListener('click', async () => {
      const url = 'https://chonkbase.net/griswold/';
      try {
        if (navigator.share) await navigator.share({ title: 'Griswold', text: 'Snow and Christmas lights for your Mac', url });
        else { await navigator.clipboard.writeText(url); share.textContent = 'Link copied'; }
      } catch (_) { /* cancelled */ }
    });
  }

  // ---------- Start ----------

  if ('IntersectionObserver' in window) {
    nearby.clear();
    let first = true;
    const watcher = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) nearby.add(entry.target); else nearby.delete(entry.target);
      }
      // The still picture has to wait until it knows what is on screen.
      if (first && !state.playing) renderStill();
      first = false;
    }, { rootMargin: '120px' });
    targets.forEach((el) => watcher.observe(el));
  }
  document.addEventListener('visibilitychange', schedule);
  window.addEventListener('resize', resize);
  window.addEventListener('scroll', () => { if (!state.playing) { followScroll(); syncLedges(); render(now, true); } }, { passive: true });
  if (reducedMotion.addEventListener) reducedMotion.addEventListener('change', () => {
    state.playing = !reducedMotion.matches;
    refreshPanel();
    schedule();
  });
  resize();
  refreshPanel();
})();
