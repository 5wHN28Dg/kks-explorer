// Course figures (docs/COURSES.md §9) for the browser client, decision 0035: the evaluator, a port of
// ref/courses.py's Figure (ref/vectors/courses-v1.json decides), and drawing on a 2D canvas. No course code runs:
// a figure is data. Exposes window.KCF = {Figure, tableAt, fmtNumber, fillTemplate, colourAt, leaderEnd, flatten,
// pointAt, draw, PALETTE}.
'use strict';
(() => {
  const PHI = 0.6180339887498949;
  const frac = x => x - Math.floor(x);

  function tableAt(t, u, step) {
    if (u < t[0][0]) return t[0][1];
    if (step) {
      let y = t[0][1];
      for (const [x, yy] of t) { if (x <= u) y = yy; else break; }
      return y;
    }
    if (u >= t[t.length - 1][0]) return t[t.length - 1][1];
    let i = 0;
    for (let j = 0; j < t.length; j++) { if (t[j][0] <= u) i = j; else break; }
    const [x0, y0] = t[i], [x1, y1] = t[i + 1];
    return y0 + (y1 - y0) * (u - x0) / (x1 - x0);
  }

  // the exact binary value of a double as num / den (den a power of two)
  function exact(x) {
    const dv = new DataView(new ArrayBuffer(8));
    dv.setFloat64(0, x);
    const hi = dv.getUint32(0), lo = dv.getUint32(4), neg = hi >>> 31, ex = (hi >>> 20) & 0x7ff;
    let m = (BigInt(hi & 0xfffff) << 32n) | BigInt(lo), e;
    if (ex === 0) e = -1074; else { m |= 1n << 52n; e = ex - 1075; }
    let num = m, den = 1n;
    if (e >= 0) num <<= BigInt(e); else den <<= BigInt(-e);
    return [neg ? -num : num, den];
  }

  // §9.7: rounded half away from zero on the exact value; minus is U+2212; no sign on a zero
  function fmtNumber(x, decimals, sign) {
    let [n, den] = exact(x);
    const neg = n < 0n;
    if (neg) n = -n;
    const p = 10n ** BigInt(decimals);
    const q = (2n * n * p + den) / (2n * den);
    let s = q.toString();
    if (decimals > 0) { s = s.padStart(decimals + 1, '0'); s = s.slice(0, -decimals) + '.' + s.slice(-decimals); }
    if (q !== 0n && neg) return '−' + s;
    return sign ? '+' + s : s;
  }

  const PLACEHOLDER = /\{\{|\}\}|\{([a-z_][a-z0-9_]{0,31})(?::(\+?)([0-6]))?\}/g;
  function fillTemplate(s, vals) {
    return s.replace(PLACEHOLDER, (tok, name, sign, dec) => {
      if (tok === '{{') return '{';
      if (tok === '}}') return '}';
      return fmtNumber(vals[name], +(dec || 0), sign === '+');
    });
  }

  function hexMix(a, b, f) {
    const ca = [1, 3, 5].map(i => parseInt(a.slice(i, i + 2), 16)), cb = [1, 3, 5].map(i => parseInt(b.slice(i, i + 2), 16));
    return '#' + ca.map((x, i) => Math.floor(x + (cb[i] - x) * f + 0.5).toString(16).padStart(2, '0')).join('');
  }

  function colourAt(stops, u) {
    if (u < stops[0][0]) return stops[0][1];
    if (u >= stops[stops.length - 1][0]) return stops[stops.length - 1][1];
    let i = 0;
    for (let j = 0; j < stops.length; j++) if (stops[j][0] <= u) i = j;
    const [x0, c0] = stops[i], [x1, c1] = stops[i + 1];
    return hexMix(c0, c1, (u - x0) / (x1 - x0));
  }

  function flatten(path, ref) {
    const pts = [];
    for (const c of path) {
      if (c[0] === 'M' || c[0] === 'L') pts.push([ref(c[1]), ref(c[2])]);
      else if (c[0] === 'C') {
        const [x0, y0] = pts[pts.length - 1];
        const [x1, y1, x2, y2, x3, y3] = c.slice(1).map(ref);
        for (let s = 1; s <= 16; s++) {
          const t = s / 16, a = (1 - t) ** 3, b = 3 * (1 - t) ** 2 * t, cc = 3 * (1 - t) * t * t, d = t ** 3;
          pts.push([a * x0 + b * x1 + cc * x2 + d * x3, a * y0 + b * y1 + cc * y2 + d * y3]);
        }
      }
    }
    const segs = [];
    for (let i = 0; i < pts.length - 1; i++) segs.push(Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]));
    return [pts, segs, segs.reduce((a, b) => a + b, 0)];
  }

  function pointAt(pts, segs, dist) {
    for (let i = 0; i < segs.length; i++) {
      const s = segs[i];
      if (dist <= s || i === segs.length - 1) {
        const f = s === 0 ? 0 : Math.min(1, Math.max(0, dist / s));
        return [pts[i][0] + (pts[i + 1][0] - pts[i][0]) * f, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * f];
      }
      dist -= s;
    }
    return pts[0];
  }

  function leaderEnd(label, at, to, anchor) {
    const [x1, y1] = at, [x2, y2] = to, w = 6.3 * [...label].length;
    const left = anchor === 'end' ? x2 - w : x2, right = left + w;
    if (x1 < left - 2) return [left - 4, y2 - 4];
    if (x1 > right + 2) return [right + 4, y2 - 4];
    return [x1, y1 > y2 ? y2 + 4 : y2 - 15];
  }

  class Figure {
    constructor(fig, reduceMotion) {
      this.f = fig;
      this.static = !('period' in fig);
      this.t = 0;
      this.v = fig.slider ? +fig.slider.init : 0;
      this.toggles = {};
      for (const tg of fig.toggles || []) this.toggles[tg.key] = tg.on ? 1 : 0;
      this.mode = 0;
      this.playing = !reduceMotion && !this.static;
      this.state = new Map();
      this.first = true;
      this.flows = [];     // [flow, particles]
      this.collect(fig.scene);
      this.vals = {};
      this.step(0);
    }
    collect(es) {
      for (const e of es) {
        if (e.flow) { const n = e.flow.count; this.flows.push([e.flow, Array.from({length: n}, (_, i) => ({k: i / n, n: 0, route: null}))]); }
        else if (e.group) this.collect(e.group);
      }
    }
    get drive() { return this.f.slider && this.f.slider.drive; }
    setSlider(v) { this.v = +v; if (this.drive) this.playing = false; }
    toggle(key) { this.toggles[key] = 1 - this.toggles[key]; this.t = 0; this.playing = true; }
    setMode(i) { this.mode = i | 0; this.playing = true; }
    play() { this.playing = true; }
    pause() { this.playing = false; }
    tick(elapsed) {
      if (this.static) return;
      elapsed = Math.min(0.05, elapsed);
      let dt = 0;
      if (this.playing) {
        dt = elapsed;
        this.t = frac(this.t + dt / this.f.period);
        if (this.drive) this.v = tableAt(this.drive.table, this.t);
      }
      this.step(dt);
    }
    ref(r) { return typeof r === 'string' ? this.vals[r] : r; }
    step(dt) {
      const vals = {};
      if (!this.static) { vals.t = this.t; vals.v = this.v; vals.mode = this.mode; Object.assign(vals, this.toggles); }
      this.vals = vals;
      for (const [name, node] of this.f.values || []) vals[name] = this.node(name, node, dt);
      for (const [fl, parts] of this.flows) this.flow(fl, parts, dt);
      this.first = false;
    }
    node(name, n, dt) {
      if ('table' in n) return tableAt(n.table, this.vals[n.of], !!n.step);
      if ('sum' in n) return n.sum.reduce((a, r) => a + this.ref(r), 0);
      if ('product' in n) return n.product.reduce((a, r) => a * this.ref(r), 1);
      if ('select' in n) { const cs = n.cases; return this.ref(cs[Math.min(cs.length - 1, Math.max(0, Math.floor(this.vals[n.select])))]); }
      if ('follow' in n) {
        const target = this.vals[n.follow];
        if (this.first) this.state.set(name, 'init' in n ? n.init : target);
        let o = this.state.get(name);
        const k = target >= o ? n.rate : ('rate_down' in n ? n.rate_down : n.rate);
        o = o + (target - o) * Math.min(1, dt * k);
        this.state.set(name, o);
        return o;
      }
      const x = this.vals[n.hold], w = this.vals[n.while] >= 0.5;
      const [held, prev] = this.state.get(name) || [x, false];
      const out = w && prev && !this.first ? held : x;
      this.state.set(name, [out, w]);
      return out;
    }
    choose(fl, i, n) {
      const u = frac((i + n * fl.count) * PHI);
      const ws = fl.routes.map(rt => Math.max(0, this.ref('weight' in rt ? rt.weight : 1)));
      const total = ws.reduce((a, b) => a + b, 0);
      if (total <= 0) return 0;
      let acc = 0;
      for (let j = 0; j < ws.length; j++) { acc += ws[j]; if (acc > u * total) return j; }
      return ws.length - 1;
    }
    flow(fl, parts, dt) {
      const ref = r => this.ref(r);
      const geo = fl.routes.map(rt => flatten(rt.path, ref));
      const along = fl.along || {};
      const speed = ref('speed' in fl ? fl.speed : 0), r0 = ref('r' in fl ? fl.r : 3), op0 = ref('opacity' in fl ? fl.opacity : 1);
      const pile = fl.pile || 0;
      const hides = (fl.hide || []).map(h => [h.rect.map(ref), ref(h.when)]);
      parts.forEach((p, i) => {
        if (p.route === null) p.route = this.choose(fl, i, 0);
        let [pts, segs, L] = geo[p.route];
        const m = along.speed ? tableAt(along.speed, p.k) : 1;
        const dk = L === 0 ? 0 : speed * m * dt / L;
        let k = p.k + dk;
        if (fl.reverse === 'pile' && dk < 0) k = Math.max(k, L === 0 ? 0 : Math.min(1, pile * frac(i * PHI) / L));
        if (k >= 1) { k -= Math.floor(k); p.n += 1; p.route = this.choose(fl, i, p.n); }
        else if (k < 0) k -= Math.floor(k);
        p.k = k;
        [pts, segs, L] = geo[p.route];
        let [x, y] = pointAt(pts, segs, k * L);
        const rt = fl.routes[p.route], lanes = rt.lanes || fl.lanes || [[0, 0]];
        const [lx, ly] = lanes[i % lanes.length].map(ref);
        const ls = along.lane ? tableAt(along.lane, k) : 1;
        x += lx * ls; y += ly * ls;
        if (fl.wrap_x) { const [a, b] = fl.wrap_x; x = a + (x - a) - (b - a) * Math.floor((x - a) / (b - a)); }
        const r = r0 * (along.r ? tableAt(along.r, k) : 1);
        let op = op0 * (along.opacity ? tableAt(along.opacity, k) : 1);
        for (const [[x0, y0, x1, y1], when] of hides) if (when >= 0.5 && x0 <= x && x <= x1 && y0 <= y && y <= y1) op = 0;
        const fill = along.fill ? tableAt(along.fill, k, true) : ('fill' in fl ? fl.fill : 'accent');
        Object.assign(p, {x, y, r, opacity: op, fill});
      });
    }
    text(t) {
      if (typeof t === 'string') return fillTemplate(t, this.vals);
      for (const c of t) if (!('when' in c) || this.ref(c.when) >= 0.5) return fillTemplate(c.text, this.vals);
      return '';
    }
    paint(p) {
      if (typeof p === 'string' || p.radial) return p;
      if (p.stops) return colourAt(p.stops, this.vals[p.of]);
      return tableAt(p.steps, this.vals[p.of], true);
    }
    scene() { return this.f.scene.map(e => this.resolve(e)); }
    resolve(e) {
      const ref = x => this.ref(x), out = {};
      for (const [k, v] of Object.entries(e)) {
        if (k === 'rect' || k === 'circle' || k === 'ellipse' || k === 'line' || k === 'at' || k === 'to') out[k] = v.map(ref);
        else if (k === 'poly') out[k] = v.map(([a, b]) => [ref(a), ref(b)]);
        else if (k === 'path') out[k] = v.map(c => [c[0], ...c.slice(1).map(ref)]);
        else if (k === 'fill' || k === 'stroke') out[k] = this.paint(v);
        else if (k === 'stroke_width' || k === 'opacity' || k === 'rx') out[k] = ref(v);
        else if (k === 'transform') out[k] = v.map(st => Object.fromEntries(Object.entries(st).map(([kk, vv]) => [kk, vv.map(ref)])));
        else if (k === 'text') out[k] = this.text(v);
        else if (k === 'clip') out[k] = {rect: v.rect.map(ref), rx: ref('rx' in v ? v.rx : 0)};
        else if (k === 'group') out[k] = v.map(c => this.resolve(c));
        else if (k === 'flow') {
          const parts = this.flows.find(([f]) => f === v)[1];
          out.flow = {particles: parts.map(p => [p.x, p.y, p.r, p.opacity, p.fill])};
          for (const kk of ['glyph', 'stroke', 'stroke_width']) if (kk in v) out.flow[kk] = kk === 'stroke_width' ? ref(v[kk]) : v[kk];
        } else out[k] = v;
      }
      if ('label' in e) out.end = leaderEnd(e.label, out.at, out.to, e.anchor || 'start');
      return out;
    }
    status() { return 'status' in this.f ? this.text(this.f.status) : null; }
    sliderText() { return this.f.slider ? this.text(this.f.slider.text) : null; }
  }

  // ---------------------------------------------------------------- drawing (§9.3–9.5)
  const PALETTE = {
    light: {ground: '#E9EDEF', surface: '#F8FAFA', sunk: '#DDE3E6', ink: '#16222B', muted: '#56646E', rule: '#C6CFD4',
            accent: '#1F5F8B', ok: '#2E7A4E', alarm: '#9A6412', alarm_fill: '#E8B04A', act: '#B3261E'},
    dark: {ground: '#11171B', surface: '#182026', sunk: '#0D1215', ink: '#E2E8EB', muted: '#95A4AD', rule: '#2B363D',
           accent: '#6DAFDC', ok: '#62C08A', alarm: '#E4AE45', alarm_fill: '#B9832A', act: '#F0776B'},
  };
  const FONTS = {body: '"Atkinson Hyperlegible", system-ui, sans-serif', display: '"Barlow Semi Condensed", "Arial Narrow", sans-serif',
                 mono: '"JetBrains Mono", ui-monospace, monospace'};

  function bbox(e) {
    if (e.rect) return [e.rect[0], e.rect[1], e.rect[2], e.rect[3]];
    if (e.circle) return [e.circle[0] - e.circle[2], e.circle[1] - e.circle[2], 2 * e.circle[2], 2 * e.circle[2]];
    if (e.ellipse) return [e.ellipse[0] - e.ellipse[2], e.ellipse[1] - e.ellipse[3], 2 * e.ellipse[2], 2 * e.ellipse[3]];
    let pts = e.poly || (e.path || []).flatMap(c => { const q = []; for (let i = 1; i < c.length; i += 2) q.push([c[i], c[i + 1]]); return q; });
    if (e.line) pts = [[e.line[0], e.line[1]], [e.line[2], e.line[3]]];
    if (!pts.length) return [0, 0, 0, 0];
    const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
    const x0 = Math.min(...xs), y0 = Math.min(...ys);
    return [x0, y0, Math.max(...xs) - x0, Math.max(...ys) - y0];
  }

  function draw(ctx, scene, pal) {
    const col = p => p === 'none' || p == null ? null : (p[0] === '#' ? p : pal[p]);
    const style = (p, e) => {
      if (p && typeof p === 'object' && p.radial) {
        const [x, y, w, h] = bbox(e), r = Math.max(w / 2, 1e-6);
        const g = ctx.createRadialGradient(x + w / 2, y + h / 2, 0, x + w / 2, y + h / 2, r);
        for (const [off, pp, op] of p.radial) {
          const c = col(pp) || '#000000';
          g.addColorStop(off, c + Math.round(Math.max(0, Math.min(1, op)) * 255).toString(16).padStart(2, '0'));
        }
        return g;
      }
      return col(p);
    };
    const rrect = (x, y, w, h, rx) => {
      rx = Math.max(0, Math.min(rx || 0, w / 2, h / 2));
      ctx.beginPath();
      if (!rx) { ctx.rect(x, y, w, h); return; }
      ctx.moveTo(x + rx, y); ctx.arcTo(x + w, y, x + w, y + h, rx); ctx.arcTo(x + w, y + h, x, y + h, rx);
      ctx.arcTo(x, y + h, x, y, rx); ctx.arcTo(x, y, x + w, y, rx); ctx.closePath();
    };
    const transform = tf => {
      for (const st of tf || []) {
        if (st.translate) ctx.translate(st.translate[0], st.translate[1]);
        else if (st.rotate) { const [d, cx, cy] = st.rotate; ctx.translate(cx, cy); ctx.rotate(d * Math.PI / 180); ctx.translate(-cx, -cy); }
        else if (st.scale) ctx.scale(st.scale[0], st.scale[1]);
      }
    };
    const paintShape = e => {
      const f = style(e.fill, e), s = col(e.stroke);
      if (f) { ctx.fillStyle = f; ctx.fill(); }
      if (s) {
        ctx.strokeStyle = s; ctx.lineWidth = 'stroke_width' in e ? e.stroke_width : 1;
        ctx.lineCap = e.cap || 'butt'; ctx.lineJoin = e.join || 'miter'; ctx.miterLimit = 4;
        ctx.setLineDash(e.dash || []);
        ctx.stroke();
      }
    };
    const el = e => {
      if ('opacity' in e && e.opacity <= 0) return;
      ctx.save();
      if ('opacity' in e) ctx.globalAlpha *= Math.min(1, e.opacity);
      transform(e.transform);
      if (e.group) {
        if (e.clip) { rrect(...e.clip.rect, e.clip.rx); ctx.clip(); }
        e.group.forEach(el);
      } else if (e.rect) { rrect(...e.rect, e.rx); paintShape(e); }
      else if (e.circle) { ctx.beginPath(); ctx.arc(e.circle[0], e.circle[1], Math.max(0, e.circle[2]), 0, 2 * Math.PI); paintShape(e); }
      else if (e.ellipse) { ctx.beginPath(); ctx.ellipse(e.ellipse[0], e.ellipse[1], Math.max(0, e.ellipse[2]), Math.max(0, e.ellipse[3]), 0, 0, 2 * Math.PI); paintShape(e); }
      else if (e.line) {
        const [x1, y1, x2, y2] = e.line;
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); paintShape(Object.assign({}, e, {fill: 'none'}));
        const s = col(e.stroke);
        if (e.arrow && s) {
          const w = 'stroke_width' in e ? e.stroke_width : 1, L = Math.hypot(x2 - x1, y2 - y1) || 1, ux = (x2 - x1) / L, uy = (y2 - y1) / L;
          const tx = x2 + 1.2 * w * ux, ty = y2 + 1.2 * w * uy, bx = tx - 6 * w * ux, by = ty - 6 * w * uy;
          ctx.setLineDash([]); ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(bx - 3 * w * uy, by + 3 * w * ux); ctx.lineTo(bx + 3 * w * uy, by - 3 * w * ux);
          ctx.closePath(); ctx.fillStyle = s; ctx.fill();
        }
      } else if (e.poly) {
        ctx.beginPath(); e.poly.forEach(([x, y], i) => i ? ctx.lineTo(x, y) : ctx.moveTo(x, y));
        if (e.closed) ctx.closePath();
        paintShape(e);
      } else if (e.path) {
        ctx.beginPath();
        for (const c of e.path) {
          if (c[0] === 'M') ctx.moveTo(c[1], c[2]); else if (c[0] === 'L') ctx.lineTo(c[1], c[2]);
          else if (c[0] === 'C') ctx.bezierCurveTo(c[1], c[2], c[3], c[4], c[5], c[6]); else ctx.closePath();
        }
        paintShape(e);
      } else if ('text' in e) {
        ctx.font = `${e.weight || 400} ${e.size || 12}px ${FONTS[e.font || 'body']}`;
        ctx.textAlign = {start: 'left', middle: 'center', end: 'right'}[e.anchor || 'start'];
        ctx.textBaseline = 'alphabetic';
        const f = 'fill' in e ? col(e.fill) : pal.ink;
        if (f) { ctx.fillStyle = f; ctx.fillText(e.text, e.at[0], e.at[1]); }
        if (col(e.stroke)) { ctx.strokeStyle = col(e.stroke); ctx.lineWidth = e.stroke_width || 1; ctx.strokeText(e.text, e.at[0], e.at[1]); }
      } else if ('label' in e) {
        ctx.fillStyle = pal.muted; ctx.beginPath(); ctx.arc(e.at[0], e.at[1], 2.5, 0, 2 * Math.PI); ctx.fill();
        ctx.strokeStyle = pal.muted; ctx.lineWidth = 1; ctx.setLineDash([]);
        ctx.beginPath(); ctx.moveTo(e.at[0], e.at[1]); ctx.lineTo(e.end[0], e.end[1]); ctx.stroke();
        ctx.font = `400 12.5px ${FONTS.body}`; ctx.textAlign = e.anchor === 'end' ? 'right' : 'left'; ctx.textBaseline = 'alphabetic';
        ctx.fillStyle = pal.ink; ctx.fillText(e.label, e.to[0], e.to[1]);
      } else if (e.flow) {
        const fl = e.flow, s = col(fl.stroke), sw = fl.stroke_width || 1;
        for (const [x, y, r, op, fill] of fl.particles) {
          if (op <= 0) continue;
          ctx.save(); ctx.globalAlpha *= Math.min(1, op);
          if (fl.glyph === 'burst') {
            if (s) {
              const d = 5 * r / 7;
              ctx.strokeStyle = s; ctx.lineWidth = sw; ctx.setLineDash([]); ctx.beginPath();
              ctx.moveTo(x - r, y); ctx.lineTo(x + r, y); ctx.moveTo(x, y - r); ctx.lineTo(x, y + r);
              ctx.moveTo(x - d, y - d); ctx.lineTo(x + d, y + d); ctx.stroke();
            }
          } else {
            ctx.beginPath(); ctx.arc(x, y, Math.max(0, r), 0, 2 * Math.PI);
            const f = col(fill); if (f) { ctx.fillStyle = f; ctx.fill(); }
            if (s) { ctx.strokeStyle = s; ctx.lineWidth = sw; ctx.setLineDash([]); ctx.stroke(); }
          }
          ctx.restore();
        }
      }
      ctx.restore();
    };
    scene.forEach(el);
  }

  window.KCF = {Figure, tableAt, fmtNumber, fillTemplate, colourAt, leaderEnd, flatten, pointAt, draw, PALETTE};
})();
