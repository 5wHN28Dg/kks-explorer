// A course in the JSON content model (docs/COURSES.md), drawn by the browser client (decision 0035). course.html?c=<id>
// loads /data/courses/<id>.json. Course data only ever goes into the page through textContent and DOM calls, never
// innerHTML. Progress uses the original courses' localStorage keys (<id>.last, .skip, .solved, .finalBest: JSON
// strings), so it carries over; course-bridge.js syncs them to the log where there is one.
'use strict';
(() => {
  const params = new URLSearchParams(location.search);
  const CID = params.get('c') || '';
  const main = document.getElementById('main'), rail = document.getElementById('rail'), mnav = document.getElementById('mnav');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const dark = matchMedia('(prefers-color-scheme: dark)');

  // ---------------------------------------------------------------- small DOM helpers
  function h(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') e.className = v;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids.flat()) if (k != null && k !== false) e.append(k instanceof Node ? k : String(k));
    return e;
  }
  const shuffle = a => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
  const plain = r => r.map(x => typeof x === 'string' ? x : x.num != null ? x.num : plain(x.b || x.i || x.small || x.term || x.link || [])).join('');

  // ---------------------------------------------------------------- progress (§8)
  const store = {
    get(k, d) { try { const v = localStorage.getItem(CID + '.' + k); return v ? JSON.parse(v) : d; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(CID + '.' + k, JSON.stringify(v)); } catch (e) { /* storage full or off */ } },
  };
  let solved = store.get('solved', {});
  function markSolved(id) { if (!solved[id]) { solved[id] = true; store.set('solved', solved); renderRail(); } }

  // ---------------------------------------------------------------- course state
  let C = null, PAGES = [], MODS = [], GLOSS = new Map();
  const moduleQs = m => [m.warm, ...m.practice, ...(m.bridge ? m.bridge.questions : [])];
  const modDone = m => moduleQs(m).every(q => solved[q.id]);
  const pageTitle = p => p.kind === 'module' ? `${p.n} · ${p.short}` : plain(p.title);

  // ---------------------------------------------------------------- runs (§3) and blocks (§4)
  function target(to) {
    if (to.url) return {href: to.url, ext: true};
    if (to.kks) return {href: '/?kks=' + encodeURIComponent(to.kks)};
    if (to.course) return {href: 'course.html?c=' + encodeURIComponent(to.course) + (to.page ? '#' + encodeURIComponent(to.page) : '')};
    return {href: '#' + encodeURIComponent(to.page)};
  }
  function runNodes(r) {
    return r.map(x => {
      if (typeof x === 'string') return document.createTextNode(x);
      if (x.b) return h('b', null, runNodes(x.b));
      if (x.i) return h('i', null, runNodes(x.i));
      if (x.small) return h('small', null, runNodes(x.small));
      if (x.num != null) return h('span', {class: 'num'}, x.num);
      if (x.term) {
        const g = GLOSS.get(x.gloss);
        return h('span', {class: 'term', tabindex: 0, title: g ? plain(g.meaning) : null}, runNodes(x.term));
      }
      if (x.link) {
        const t = target(x.to);
        return h('a', {href: t.href, target: t.ext ? '_blank' : null, rel: t.ext ? 'noopener' : null}, runNodes(x.link));
      }
      return document.createTextNode('');
    });
  }
  function blocks(bs) { return bs.map(block); }
  function block(b) {
    if (b.h) return h(b.level === 2 ? 'h2' : 'h3', null, runNodes(b.h));
    if (b.p) return h('p', null, runNodes(b.p));
    if (b.ul || b.ol) return h(b.ul ? 'ul' : 'ol', null, (b.ul || b.ol).map(r => h('li', null, runNodes(r))));
    if (b.table) return table(b.table);
    if (b.callout) {
      const cls = b.callout === 'flag' ? 'flag' : 'why ' + b.callout;
      return h('div', {class: cls, role: 'note'}, b.callout === 'flag' ? h('b', null, runNodes(b.label), ' ') : h('span', {class: 'tag'}, runNodes(b.label)),
               b.body.length === 1 && b.body[0].p && b.callout === 'flag' ? runNodes(b.body[0].p) : blocks(b.body));
    }
    if (b.cards) return h('div', {class: 'intro-grid'}, b.cards.map(([t, x]) => h('div', null, h('b', null, runNodes(t)), runNodes(x))));
    if (b.chain) {
      const kids = [];
      b.chain.forEach((r, i) => { if (i) kids.push(h('span', {class: 'arr', 'aria-hidden': 'true'}, '→')); kids.push(h('span', {class: 'link'}, runNodes(r))); });
      return h('div', {class: 'chain', role: 'list'}, kids.map(k => (k.className === 'link' && k.setAttribute('role', 'listitem'), k)));
    }
    if (b.figure) return figure(b.figure);
    if (b.image) {
      const im = b.image;
      return h('figure', {class: 'photo'},
        h('img', {src: '/data/courses/' + encodeURIComponent(im.file), width: im.w, height: im.h, alt: im.alt, loading: 'lazy'}),
        (im.caption.length || im.credit.length) ? h('figcaption', null, runNodes(im.caption),
          im.credit.length ? h('span', {class: 'credit'}, runNodes(im.credit)) : null) : null);
    }
    if (b.issues) {
      return h('ul', {class: 'issues'}, b.issues.map(([sev, t, x]) => h('li', null,
        h('span', {class: 'pill ' + {high: 'act', medium: 'alarm', low: 'ok'}[sev]}, sev[0].toUpperCase() + sev.slice(1)), ' ',
        h('b', null, runNodes(t), '.'), ' ', runNodes(x))));
    }
    if (b.tool === 'kks_decoder') return kksTool();
    return document.createTextNode('');
  }
  function table(t) {
    const num = new Set(t.num);
    return h('div', {class: 'tablewrap', tabindex: 0, role: 'region', 'aria-label': plain(t.head[0] || []) || 'Table'},
      h('table', null, h('thead', null, h('tr', null, t.head.map(c => h('th', {scope: 'col'}, runNodes(c))))),
        h('tbody', null, t.rows.map(r => h('tr', null, r.map((c, i) => h('td', {class: num.has(i) ? 'v' : null}, runNodes(c))))))));
  }

  // ---------------------------------------------------------------- figures (§9)
  const live = new Set();      // animated figures on the page
  const shown = new Set();     // every figure on the page (repainted for fonts, size and theme)
  let raf = 0;
  function figure(id) {
    const f = C.figures[id];
    const ev = new KCF.Figure(f, reduceMotion.matches);
    const canvas = h('canvas', {role: 'img', 'aria-label': f.title});
    const desc = h('p', {class: 'sr', id: 'fd-' + id + '-' + Math.random().toString(36).slice(2, 8)}, f.alt);
    canvas.setAttribute('aria-describedby', desc.id);
    const status = h('div', {class: 'vis-state'});
    const ctrl = h('div', {class: 'vis-ctrl'});
    const box = h('figure', {class: 'vis'},
      h('div', {class: 'vis-head'}, h('span', {class: 'vis-title'}, f.title), h('span', {class: 'vis-tag'}, ev.static ? '' : 'animated')),
      h('div', {class: 'vis-stage'}, canvas), desc, ev.static ? null : status, ev.static ? null : ctrl,
      f.caption.length ? h('figcaption', {class: 'figcap'}, runNodes(f.caption)) : null);
    const st = {ev, canvas, status, f, visible: false, last: 0, slider: null, out: null, playBtn: null, scale: 1};
    if (!ev.static) {
      st.playBtn = h('button', {class: 'vis-btn', type: 'button', onclick: () => { ev.playing ? ev.pause() : ev.play(); sync(st); }});
      ctrl.append(st.playBtn);
      if (f.slider) {
        st.slider = h('input', {type: 'range', min: 0, max: 1, step: 0.001, value: ev.v,
          oninput: () => { ev.setSlider(+st.slider.value); ev.tick(0); paint(st); sync(st); }});
        st.out = h('span', {class: 'vis-out', 'aria-hidden': 'true'});
        ctrl.append(h('label', null, f.slider.label, st.slider, st.out));
      }
      for (const tg of f.toggles || []) {
        const cb = h('input', {type: 'checkbox', onchange: () => { ev.toggle(tg.key); cb.checked = !!ev.toggles[tg.key]; sync(st); }});
        cb.checked = !!ev.toggles[tg.key];
        ctrl.append(h('label', {style: 'flex:0 0 auto'}, cb, tg.label));
      }
      if (f.modes) {
        const name = 'm' + Math.random().toString(36).slice(2, 8);
        ctrl.append(h('div', {class: 'chips', role: 'radiogroup', 'aria-label': f.title}, f.modes.map((m, i) => {
          const r = h('input', {type: 'radio', name, checked: i === 0, onchange: () => { ev.setMode(i); sync(st); }});
          return h('label', {style: 'flex:0 0 auto'}, r, m.label);
        })));
      }
      live.add(st);
      io.observe(canvas);
      canvas._st = st;
    }
    shown.add(st);
    requestAnimationFrame(() => { size(st); paint(st); sync(st); });
    return box;
  }
  function size(st) {
    // §9.8: scaled to the width available, never above 1:1, never below min(w, 520) (then the stage scrolls)
    const avail = st.canvas.parentElement ? st.canvas.parentElement.clientWidth : st.f.w;
    const w = Math.max(Math.min(st.f.w, 520), Math.min(st.f.w, avail || st.f.w));
    st.scale = w / st.f.w;
    const dpr = window.devicePixelRatio || 1;
    st.canvas.style.width = w + 'px';
    st.canvas.style.height = st.f.h * st.scale + 'px';
    st.canvas.width = Math.round(w * dpr);
    st.canvas.height = Math.round(st.f.h * st.scale * dpr);
    st.dpr = dpr;
  }
  function paint(st) {
    const ctx = st.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, st.canvas.width, st.canvas.height);
    ctx.setTransform(st.dpr * st.scale, 0, 0, st.dpr * st.scale, 0, 0);
    KCF.draw(ctx, st.ev.scene(), dark.matches ? KCF.PALETTE.dark : KCF.PALETTE.light);
  }
  function sync(st) {
    const ev = st.ev;
    if (st.playBtn) st.playBtn.textContent = ev.playing ? 'Pause' : 'Play';
    if (st.slider) {
      if (document.activeElement !== st.slider) st.slider.value = ev.v;
      const t = ev.sliderText();
      st.out.textContent = t;
      st.slider.setAttribute('aria-valuetext', t);
    }
    const s = ev.status();
    if (s != null) st.status.textContent = s;
    if ((ev.playing || [...live].some(x => x.ev.playing)) && !raf) raf = requestAnimationFrame(frame);
  }
  function frame(now) {
    raf = -1;   // busy: sync() below must not schedule a second callback
    let any = false;
    for (const st of live) {
      if (!st.canvas.isConnected) { live.delete(st); continue; }
      const elapsed = st.last ? (now - st.last) / 1000 : 0;
      st.last = now;
      if (!st.visible || !st.ev.playing) { st.last = 0; continue; }   // §9.6: off screen = frozen
      st.ev.tick(elapsed);
      paint(st); sync(st);
      any = true;
    }
    raf = any || [...live].some(st => st.ev.playing) ? requestAnimationFrame(frame) : 0;
  }
  const io = new IntersectionObserver(es => {
    for (const e of es) if (e.target._st) { e.target._st.visible = e.isIntersecting; e.target._st.last = 0; }
    if (!raf) raf = requestAnimationFrame(frame);
  });
  const repaintAll = resize => { for (const st of shown) { if (resize) size(st); paint(st); } };
  dark.addEventListener('change', () => repaintAll(false));
  addEventListener('resize', () => repaintAll(true));

  // ---------------------------------------------------------------- the KKS decoder (0025: the app's decoder)
  let KKSDATA = null;
  function kksTool() {
    const inp = h('input', {class: 'kksin', id: 'kksin', value: '11 LAB 70 AA 501', autocomplete: 'off', spellcheck: 'false'});
    const out = h('div', {'aria-live': 'polite'});
    const decode = async () => {
      KKSDATA ??= await fetch('/data/kks.json', {credentials: 'same-origin'}).then(r => r.json()).catch(() => ({}));
      const raw = inp.value.toUpperCase().replace(/[\s_.\-]/g, '');
      const m = raw.match(/^(\d{2})([A-Z]{3})(\d{2})([A-Z]{2})(\d{3})([A-Z]?)$/);
      out.replaceChildren();
      if (!m) { out.append(h('div', {class: 'fb wrong'}, h('b', null, "Can't read that code."), 'Expected something like 11 LAB 70 AA 501: unit digits, three system letters, two digits, two equipment letters, three digits.')); return; }
      const [, unit, sys, sn, eq, en, suf] = m, D = KKSDATA;
      const rows = [[unit, 'Unit', (D.blocks || {})[unit] || 'not in the plant tables'],
                    [sys, 'System', (D.systems || {})[sys] || 'not in the plant tables'],
                    [sn, 'System number', 'section ' + sn + ' of that system'],
                    [eq, 'Equipment type', (D.components || {})[eq] || 'not in the plant tables'],
                    [en, 'Equipment number', 'item ' + en]];
      if (suf) rows.push([suf, 'Suffix', 'a letter after the number (e.g. R, K: a second element of the same item)']);
      out.append(table({head: [['Part'], ['Is'], ['Meaning']], rows: rows.map(r => [[{num: r[0]}], [r[1]], [r[2]]]), num: []}),
        h('p', null, h('a', {href: '/?kks=' + encodeURIComponent(raw)}, 'Find ' + raw + ' on the drawings')));
    };
    inp.addEventListener('input', decode);
    setTimeout(decode);
    return h('div', {class: 'act'}, h('label', {for: 'kksin', class: 'kind'}, h('span', null, 'KKS code')), inp, out);
  }

  // ---------------------------------------------------------------- questions (§5)
  function feedback(ok, head, why) { return h('div', {class: 'fb ' + (ok ? 'right' : 'wrong'), role: 'status'}, h('b', null, head), why && why.length ? runNodes(why) : null); }
  function question(q, label, opts = {}) {
    // opts: suffix (_r, _f, _p), once (tests: the first pick counts), onAnswer(ok)
    const id = q.id + (opts.suffix || '');
    const fb = h('div', {class: 'fbwrap'});
    const kind = h('div', {class: 'kind'}, h('span', null, label || (q.type === 'scenario' ? 'Scenario' : q.type === 'order' ? 'Put in order' : 'Practice')),
                   q.src.length ? h('span', {class: 'src'}, runNodes(q.src)) : null);
    const qid = 'q-' + id;
    const box = h('div', {class: 'act', role: 'group', 'aria-labelledby': qid}, kind);
    if (q.type === 'scenario') box.append(h('div', {class: 'panel'}, q.panel.map(r => h('div', {class: 'tag-r'},
      h('span', null, runNodes(r.name)), h('span', {class: 'val ' + r.state}, runNodes(r.value))))));
    box.append(h('div', {class: 'q', id: qid}, runNodes(q.q)));
    if (q.type === 'order') {
      const seq = h('div', {class: 'seq', 'aria-label': 'Your order'}), pool = h('div', {class: 'pool', 'aria-label': 'Steps to place'});
      const order = shuffle(q.steps.map((_, i) => i));
      let chosen = [];
      const step = (i, n) => h('button', {class: 'step', type: 'button', 'data-i': i, onclick: () => {
        chosen = n ? chosen.filter(x => x !== i) : chosen.concat(i); fb.replaceChildren(); draw();
        const again = (n ? pool : seq).querySelector(`[data-i="${i}"]`); if (again) again.focus(); }},
        h('span', {class: 'i'}, n ? String(n) : '·'), h('span', null, runNodes(q.steps[i])));
      const draw = () => { seq.replaceChildren(...chosen.map((i, k) => step(i, k + 1))); pool.replaceChildren(...order.filter(i => !chosen.includes(i)).map(i => step(i, 0))); };
      box.append(seq, pool, h('div', {class: 'row'},
        h('button', {class: 'btn', type: 'button', onclick: () => {
          if (chosen.length < q.steps.length) { fb.replaceChildren(feedback(false, 'Not finished.', [`Place all ${q.steps.length} steps first.`])); return; }
          const good = chosen.map((i, k) => i === k);
          [...seq.children].forEach((b, k) => b.classList.add(good[k] ? 'right' : 'wrong'));
          const n = good.filter(Boolean).length;
          if (n === q.steps.length) { fb.replaceChildren(feedback(true, 'All in the right order.')); markSolved(id); }
          else fb.replaceChildren(feedback(false, `${n} of ${q.steps.length} in the right place.`, ['Red steps are out of position. Take a step back by pressing it, or start again.']));
        }}, 'Check order'),
        h('button', {class: 'btn ghost', type: 'button', onclick: () => { chosen = []; fb.replaceChildren(); draw(); }}, 'Start again')), fb);
      draw();
      return box;
    }
    const optsBox = h('div', {class: 'opts'});
    let first = true;
    q.options.forEach((o, i) => {
      const b = h('button', {class: 'opt', type: 'button', onclick: () => {
        if (opts.once && !first) return;
        optsBox.querySelectorAll('.opt').forEach(x => x.classList.remove('wrong'));
        b.classList.add(o.right ? 'right' : 'wrong');
        b.setAttribute('aria-pressed', 'true');
        fb.replaceChildren(feedback(o.right, o.right ? 'Right.' : 'Not quite.', o.why));
        if (opts.once) {
          if (!o.right) {
            const ri = q.options.findIndex(x => x.right);
            optsBox.children[ri].classList.add('right');
            fb.append(h('div', {class: 'fb right'}, h('b', null, 'Correct answer:'), runNodes(q.options[ri].text), ' ', runNodes(q.options[ri].why)));
          }
          optsBox.querySelectorAll('.opt').forEach(x => x.setAttribute('aria-disabled', 'true'));
        }
        if (first) { first = false; opts.onAnswer && opts.onAnswer(o.right); }
        if (o.right) markSolved(id);
      }}, runNodes(o.text));
      optsBox.append(b);
    });
    box.append(optsBox, fb);
    return box;
  }

  // ---------------------------------------------------------------- pages (§6, §7)
  function head(eyebrow, title) { return [h('div', {class: 'eyebrow'}, eyebrow), h('h1', {tabindex: -1}, runNodes(title))]; }
  function nextPrev(p) {
    const i = PAGES.indexOf(p), prv = PAGES[i - 1], nxt = PAGES[i + 1];
    return h('div', {class: 'foot'},
      prv ? h('a', {class: 'btn ghost', href: '#' + prv.id}, '← ' + pageTitle(prv)) : h('span'),
      nxt ? h('a', {class: 'btn', href: '#' + nxt.id}, pageTitle(nxt) + ' →') : h('span'));
  }
  function modulePage(m) {
    const idx = MODS.indexOf(m);
    const pool = MODS.slice(0, idx).flatMap(x => x.practice.filter(q => q.type !== 'order'));
    const recall = shuffle(pool).slice(0, 2);
    const out = [...head('Module ' + m.n, m.title)];
    if (m.goals.length) out.push(h('div', {class: 'goal'}, h('b', null, 'After this module you can'), h('ul', null, m.goals.map(g => h('li', null, runNodes(g))))));
    if (recall.length) out.push(h('h2', null, 'From earlier modules'), h('p', null, 'Two questions from what you have already covered. Answer from memory.'),
                                ...recall.map(q => question(q, 'Recall', {suffix: '_r'})));
    out.push(h('h2', null, 'Guess first'), question(m.warm, 'Before the lesson'));
    out.push(h('h2', null, m.n === '0' ? 'About this course' : 'The lesson'), ...blocks(m.body));
    if (m.worked) {
      const steps = h('div', {class: 'wsteps', 'aria-live': 'polite'});
      let k = 0;
      const btn = h('button', {class: 'btn ghost', type: 'button', onclick: () => {
        if (k < m.worked.steps.length) { const [l, t] = m.worked.steps[k]; steps.append(h('div', {class: 'wstep'}, h('span', {class: 'lbl'}, `Step ${k + 1} · `, runNodes(l)), runNodes(t))); k++; }
        if (k >= m.worked.steps.length) { btn.textContent = 'All steps shown'; btn.disabled = true; }
      }}, 'Predict the next step, then reveal it');
      out.push(h('h2', null, 'Worked example'), h('div', {class: 'worked'}, h('div', {class: 'kind'}, 'Worked example'),
        h('div', {class: 'case'}, runNodes(m.worked.case)), steps, h('div', {class: 'row'}, btn)));
    }
    if (m.practice.length) out.push(h('h2', null, 'Practice'), h('p', null, 'Every wrong answer tells you why. Retry until each is right.'),
                                    ...m.practice.map(q => question(q)));
    if (m.bridge) out.push(h('h2', null, runNodes(m.bridge.title)), m.bridge.intro.length ? h('p', null, runNodes(m.bridge.intro)) : null,
                           ...m.bridge.questions.map(q => question(q, 'Bridge')));
    out.push(nextPrev(m));
    return out;
  }
  function placementPage(p) {
    const res = {}, plan = h('div', {class: 'stat', 'aria-live': 'polite'}, `Answer all ${p.items.length} to see which modules to take.`);
    let answered = 0;
    const qs = p.items.map((it, i) => question(it.q, `Q${i + 1} · ${pageTitle(MODS.find(m => m.id === it.module))}`, {suffix: '_p', once: true, onAnswer: ok => {
      const r = res[it.module] ??= {n: 0, ok: 0}; r.n++; if (ok) r.ok++;
      if (++answered < p.items.length) return;
      const skip = {}, take = [];
      for (const m of MODS) { const r = res[m.id]; if (r && r.ok === r.n) skip[m.id] = true; else if (r) take.push(m); }
      store.set('skip', skip); renderRail();
      plan.replaceChildren(h('p', null, h('b', null, 'Take: '), take.length ? take.flatMap((m, j) => [j ? ', ' : '', h('a', {href: '#' + m.id}, pageTitle(m))]) : 'none.'),
                           h('p', null, h('b', null, 'Can skip: '), Object.keys(skip).length ? Object.keys(skip).map(id => pageTitle(MODS.find(m => m.id === id))).join(', ') : 'none.'));
    }}));
    return [...head('Test', p.title), ...blocks(p.intro), ...qs, h('div', {class: 'act'}, h('div', {class: 'kind'}, h('span', null, 'Your plan')), plan)];
  }
  function testPage(p) {
    const byId = new Map();
    for (const m of MODS) for (const q of moduleQs(m)) byId.set(q.id, q);
    let items = shuffle(p.items.map(it => ({m: it.module, q: it.q || byId.get(it.ref)})));
    if (p.draw != null) items = items.slice(0, p.draw);
    let score = 0, answered = 0;
    const missed = new Set(), scoreEl = h('div', {class: 'score', 'aria-live': 'polite'}, `0 / ${items.length} answered`), more = h('div', {class: 'stat'});
    const qs = items.map((it, i) => question(it.q, `Question ${i + 1} of ${items.length}`, {suffix: '_f', once: true, onAnswer: ok => {
      answered++; if (ok) score++; else missed.add(it.m);
      scoreEl.textContent = `${score} / ${answered} right${answered === items.length ? ' · finished' : ''}`;
      if (answered < items.length) return;
      if (score > store.get('finalBest', 0)) store.set('finalBest', score);
      const passed = score >= p.pass;
      more.replaceChildren(...blocks(passed ? p.on_pass : p.on_fail));
      if (!passed || missed.size) more.append(h('p', null, missed.size ? ['Revisit: ', ...[...missed].flatMap((id, j) => [j ? ', ' : '', h('a', {href: '#' + id}, pageTitle(MODS.find(m => m.id === id)))])] : null));
    }}));
    const best = store.get('finalBest', 0);
    return [...head('Test', p.title), ...blocks(p.intro), best ? h('p', {class: 'stat'}, `Your best so far: ${best}`) : null, ...qs,
            h('div', {class: 'act'}, h('div', {class: 'kind'}, h('span', null, 'Result')), scoreEl, more)];
  }
  function vocabPage(p) {
    const G = C.glossary, st = {n: 0, ok: 0, streak: 0};
    const term = h('div', {class: 'reading', style: 'font-family:var(--display);font-size:32px', 'aria-live': 'polite'}), mod = h('div', {class: 'p'});
    const opts = h('div', {class: 'opts'}), fb = h('div', {class: 'fbwrap'}), stat = h('span', {class: 'stat'});
    const pick = () => {
      const cur = G[Math.floor(Math.random() * G.length)];
      let done = false;
      mod.textContent = 'Module ' + pageTitle(MODS.find(m => m.id === cur.module));
      term.textContent = cur.term;
      fb.replaceChildren();
      opts.replaceChildren(...shuffle([cur, ...shuffle(G.filter(g => g !== cur)).slice(0, 3)]).map(g => {
        const b = h('button', {class: 'opt', type: 'button', onclick: () => {
          if (done) return; done = true;
          const ok = g === cur; st.n++; if (ok) { st.ok++; st.streak++; } else st.streak = 0;
          b.classList.add(ok ? 'right' : 'wrong');
          if (!ok) [...opts.children].find(x => x._g === cur).classList.add('right');
          fb.replaceChildren(ok ? feedback(true, 'Right.') : feedback(false, 'Not quite.', ['You picked the meaning of ', {b: [g.term]}, '.']));
          stat.textContent = `${st.ok}/${st.n} right · streak ${st.streak}`;
        }}, runNodes(g.meaning));
        b._g = g;
        return b;
      }));
    };
    pick();
    return [...head('Practice', p.title), ...blocks(p.intro), h('div', {class: 'act'}, h('div', {class: 'kind'}, h('span', null, 'What does it mean?'), stat),
            h('div', {class: 'drill-card'}, mod, term), opts, fb, h('div', {class: 'row'}, h('button', {class: 'btn', type: 'button', onclick: pick}, 'Next term')))];
  }
  function readingPage(p) {
    const cats = [...new Set(p.items.map(d => d.cat))], on = new Set(cats), st = {n: 0, ok: 0, streak: 0};
    const card = h('div', {class: 'drill-card', 'aria-live': 'polite'}), fb = h('div', {class: 'fbwrap'}), stat = h('span', {class: 'stat'});
    let cur = null, answered = false;
    const LBL = {ok: 'within limits', alarm: 'in alarm', act: 'beyond the action limit'};
    const judgeBtns = [['ok', 'Within limits', 'no alarm'], ['alarm', 'Alarm', 'investigate, correct'], ['act', 'Beyond limit', "stop, hold, trip, don't start"]].map(([a, t, s]) => {
      const b = h('button', {class: 'opt', type: 'button', onclick: () => {
        if (!cur || answered) return; answered = true;
        const ok = a === cur.a; st.n++; if (ok) { st.ok++; st.streak++; } else st.streak = 0;
        b.classList.add(ok ? 'right' : 'wrong'); if (!ok) judgeBtns.find(x => x._a === cur.a).classList.add('right');
        fb.replaceChildren(feedback(ok, `${ok ? 'Right' : 'Not quite'}: ${LBL[cur.a]}.`, cur.d.note));
        stat.textContent = `${st.ok}/${st.n} right · streak ${st.streak}`;
      }}, t, h('small', null, s));
      b._a = a;
      return b;
    });
    const judge = (d, v) => { for (const [op, lim, s] of d.rules) if ({'>=': v >= lim, '>': v > lim, '<=': v <= lim, '<': v < lim}[op]) return s; return 'ok'; };
    const pick = () => {
      const pool = p.items.filter(d => on.has(d.cat));
      judgeBtns.forEach(b => b.classList.remove('right', 'wrong')); fb.replaceChildren(); answered = false;
      if (!pool.length) { cur = null; card.replaceChildren(h('div', {class: 'p'}, 'Pick at least one topic.')); return; }
      const d = pool[Math.floor(Math.random() * pool.length)], v = d.values[Math.floor(Math.random() * d.values.length)];
      cur = {d, v, a: judge(d, v)};
      const vs = (v > 0 && d.unit === 'mm' ? '+' : '') + String(v).replace('-', '−');
      card.replaceChildren(h('div', {class: 'p'}, runNodes(d.name)), h('div', {class: 'reading'}, vs, ' ', h('span', {style: 'font-size:18px'}, d.unit)),
                           h('div', {class: 'ctx'}, runNodes(d.context)));
    };
    const chips = h('div', {class: 'chips', role: 'group', 'aria-label': 'Topics'}, cats.map(c => {
      const b = h('button', {class: 'chip', type: 'button', 'aria-pressed': 'true', onclick: () => {
        on.has(c) ? on.delete(c) : on.add(c); b.setAttribute('aria-pressed', String(on.has(c))); pick(); }}, c);
      return b;
    }));
    pick();
    return [...head('Practice', p.title), ...blocks(p.intro), chips, h('div', {class: 'act'}, h('div', {class: 'kind'}, h('span', null, 'Is this reading OK?'), stat),
            card, h('div', {class: 'judge'}, judgeBtns), fb, h('div', {class: 'row'}, h('button', {class: 'btn', type: 'button', onclick: pick}, 'Next reading')))];
  }
  function glossaryPage(p) {
    const out = [...head('Reference', p.title), ...blocks(p.intro)];
    for (const m of MODS) {
      const rows = C.glossary.filter(g => g.module === m.id);
      if (rows.length) out.push(h('h2', null, `${m.n} · `, runNodes(m.title)), table({head: [['Term'], ['Meaning']], rows: rows.map(g => [[{b: [g.term]}], g.meaning]), num: []}));
    }
    return out;
  }
  function freePage(p) { return [...head(p.eyebrow, p.title), ...blocks(p.intro), ...blocks(p.body)]; }

  // ---------------------------------------------------------------- rail, routing
  function renderRail() {
    if (!C) return;
    const cur = currentId(), skip = store.get('skip', {});
    const all = MODS.flatMap(moduleQs), done = all.filter(q => solved[q.id]).length;
    const btn = p => h('a', {href: '#' + p.id, 'aria-current': cur === p.id ? 'page' : null, class: 'railbtn'},
      h('span', {class: 'n'}, p.kind === 'module' ? p.n : '·'),
      h('span', null, p.kind === 'module' ? p.short : plain(p.title), p.kind === 'module' && skip[p.id] ? h('span', {class: 'stat'}, ' · can skip') : null),
      p.kind === 'module' ? h('span', {class: 'tick' + (modDone(p) ? ' done' : ''), role: 'img', 'aria-label': modDone(p) ? 'complete' : 'not complete'}) : h('span'));
    rail.replaceChildren(h('h4', null, 'Modules'), ...MODS.map(btn),
      h('div', {class: 'progress', role: 'progressbar', 'aria-valuemin': 0, 'aria-valuemax': all.length, 'aria-valuenow': done, 'aria-label': 'Questions solved'},
        h('i', {style: `width:${all.length ? Math.round(done / all.length * 100) : 0}%`})),
      h('div', {class: 'stat', style: 'margin:4px 8px 0'}, `${done}/${all.length} solved`),
      h('h4', null, 'Tests & reference'), ...PAGES.filter(p => p.kind !== 'module').map(btn));
    const sel = h('select', {id: 'mnavsel', onchange: () => { location.hash = sel.value; }}, PAGES.map(p => h('option', {value: p.id, selected: p.id === cur}, pageTitle(p))));
    mnav.replaceChildren(h('label', {for: 'mnavsel'}, 'Go to'), sel);
  }
  function currentId() {
    const id = decodeURIComponent(location.hash.slice(1));
    return PAGES.some(p => p.id === id) ? id : (PAGES.some(p => p.id === store.get('last', '')) ? store.get('last', '') : PAGES[0].id);
  }
  function render() {
    const id = currentId(), p = PAGES.find(x => x.id === id);
    store.set('last', id);
    live.clear(); shown.clear();
    const kids = {module: modulePage, placement: placementPage, test: testPage, vocab_drill: vocabPage, reading_drill: readingPage,
                  glossary: glossaryPage, page: freePage}[p.kind](p);
    main.replaceChildren(...kids.filter(Boolean));
    renderRail();
    document.title = pageTitle(p) + ' — ' + C.title;
    const h1 = main.querySelector('h1');
    if (h1 && render.done) h1.focus({preventScroll: true});
    render.done = true;
    window.scrollTo(0, 0);
  }

  async function start() {
    try {
      if (!/^[a-z_][a-z0-9_]{0,31}$/.test(CID)) throw new Error('No course chosen.');
      const r = await fetch('/data/courses/' + CID + '.json', {credentials: 'same-origin'});
      if (!r.ok) throw new Error('The course is not available (' + r.status + ').');
      const c = await r.json();
      if (c.format !== 'kks-course' || c.version !== 1) throw new Error('This course needs a newer version of the program.');
      C = c;
    } catch (e) {
      main.replaceChildren(h('div', {class: 'err', role: 'alert'}, String(e.message || e)));
      return;
    }
    PAGES = C.pages; MODS = PAGES.filter(p => p.kind === 'module');
    for (const g of C.glossary) GLOSS.set(g.term, g);
    document.getElementById('brand').replaceChildren(C.title, h('small', null, C.short));
    if (document.fonts && document.fonts.load) {   // canvas text needs the course faces loaded
      Promise.all(['400 12px "Atkinson Hyperlegible"', '600 12px "Barlow Semi Condensed"', '400 12px "JetBrains Mono"'].map(f => document.fonts.load(f)))
        .then(() => repaintAll(false)).catch(() => {});
    }
    addEventListener('hashchange', render);
    render();
  }
  start();
})();
