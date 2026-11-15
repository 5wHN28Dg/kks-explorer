// UI audit (tools/ui_audit): read by audit_web.py and injected into each page; not run on its own.
// Injected by audit_web.py: measures the page as it is. Returns targets (clickable/focusable, with bounds), texts
// (font size, colour, effective background, WCAG ratio), overflow and code-identifier facts.
(() => {
  const vis = el => { const s = getComputedStyle(el); if (s.display === 'none' || s.visibility === 'hidden' || +s.opacity === 0) return false;
    const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 };
  const shown = el => { for (let e = el; e && e !== document.documentElement; e = e.parentElement) { const s = getComputedStyle(e);
    if (s.display === 'none' || s.visibility === 'hidden') return false } return true };
  const name = el => (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || el.value || el.placeholder || '').trim().replace(/\s+/g, ' ').slice(0, 50);
  const path = el => { const p = []; for (let e = el; e && e !== document.body && p.length < 4; e = e.parentElement)
    p.unshift(e.localName + (e.id ? '#' + e.id : '') + (e.classList.length ? '.' + [...e.classList].slice(0, 2).join('.') : '')); return p.join('>') };
  // targets
  const hit = el => { const r = el.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + r.height / 2;
    if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) return false; const t = document.elementFromPoint(x, y);
    return !!t && (t === el || el.contains(t) || (el.localName === 'input' && t.localName === 'label' && t.contains(el))) };
  const SEL = 'a[href],button,input:not([type=hidden]),select,textarea,summary,label,[role=button],[role=option],[role=tab],[role=link],[tabindex]';
  const cands = new Set(document.querySelectorAll(SEL));
  for (const el of document.querySelectorAll('body *')) if (getComputedStyle(el).cursor === 'pointer' && !el.closest(SEL)) cands.add(el);
  const targets = [];
  for (const el of cands) {
    if (!vis(el) || !shown(el)) continue;
    if (el.closest('#layer') && !el.matches('#layer > *')) continue;
    if (el.localName === 'label' && !el.querySelector('input,select,textarea') && !el.htmlFor) continue;
    if (el.localName === 'input' && el.type !== 'file' && getComputedStyle(el).display === 'none') continue;
    const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    // a text link inside a paragraph is exempt (T1/T3): inline <a> whose parent has other text
    const inline = el.localName === 'a' && s.display === 'inline' && el.parentElement && el.parentElement.textContent.trim().length > el.textContent.trim().length + 3;
    targets.push({tag: el.localName, id: el.id || '', cls: el.className && el.className.baseVal === undefined ? String(el.className).slice(0, 40) : '', name: name(el), path: path(el),
      x: Math.round(r.left), y: Math.round(r.top), w: +r.width.toFixed(1), h: +r.height.toFixed(1),
      focusable: el.tabIndex >= 0 && !el.disabled, hit: hit(el), pointer: s.cursor === 'pointer', tabindex: el.getAttribute('tabindex'), onDrawing: !!el.closest('#layer'), inline,
      userSelect: s.userSelect || s.webkitUserSelect, semantic: el.matches(SEL)});
  }
  // overlaps between targets that are not nested
  const els = []; for (const el of cands) if (vis(el) && shown(el) && !el.closest('#layer') && hit(el)) els.push(el);
  const overlaps = [];
  for (let i = 0; i < els.length && overlaps.length < 60; i++) for (let j = i + 1; j < els.length; j++) {
    const a = els[i], b = els[j]; if (a.contains(b) || b.contains(a)) continue;
    if ((a.localName === 'label' && a.contains(b)) || (b.localName === 'label')) continue;
    const r = a.getBoundingClientRect(), q = b.getBoundingClientRect();
    const ix = Math.min(r.right, q.right) - Math.max(r.left, q.left), iy = Math.min(r.bottom, q.bottom) - Math.max(r.top, q.top);
    if (ix > 1 && iy > 1 && !(a.closest('#layer') && b.closest('#layer'))) overlaps.push([name(a) + ' <' + a.localName + '>', name(b) + ' <' + b.localName + '>', Math.round(ix), Math.round(iy)]);
  }
  // colours
  const parse = c => { const m = c.match(/rgba?\(([^)]+)\)/); if (!m) return null; const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number);
    return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1] };
  const over = (top, bot) => { const a = top[3]; return [top[0] * a + bot[0] * (1 - a), top[1] * a + bot[1] * (1 - a), top[2] * a + bot[2] * (1 - a), 1] };
  const bgOf = el => { const layers = []; let hasImg = false;
    for (let e = el; e; e = e.parentElement) { const s = getComputedStyle(e); const c = parse(s.backgroundColor);
      if (s.backgroundImage && s.backgroundImage !== 'none') hasImg = true;
      if (c && c[3] > 0) { layers.push(c); if (c[3] >= 1) break } }
    let base = [255, 255, 255, 1]; for (let i = layers.length - 1; i >= 0; i--) base = over(layers[i], base); return {bg: base, hasImg} };
  const lum = c => { const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]) };
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05) };
  const texts = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const seen = new Set();
  for (let n; (n = walker.nextNode());) {
    if (!n.textContent.trim()) continue; const el = n.parentElement; if (!el || seen.has(el)) continue; seen.add(el);
    if (!vis(el) || !shown(el) || el.closest('script,style,option,.vh,svg,canvas')) continue;
    const s = getComputedStyle(el); const fg = parse(s.color); const {bg, hasImg} = bgOf(el);
    const fgc = fg[3] < 1 ? over(fg, bg) : fg;
    // opacity of ancestors dims the text
    let op = 1; for (let e = el; e; e = e.parentElement) op *= +getComputedStyle(e).opacity;
    const eff = op < 1 ? over([fgc[0], fgc[1], fgc[2], op], bg) : fgc;
    const fs = parseFloat(s.fontSize), fw = +s.fontWeight || 400;
    const disabled = !!el.closest('button:disabled,input:disabled,[aria-disabled=true]');
    const code = !!el.closest('.kks,.mono,.k,code,.id');
    texts.push({t: n.textContent.trim().replace(/\s+/g, ' ').slice(0, 40), path: path(el), fs, fw, color: s.color, bg: 'rgb(' + bg.slice(0, 3).map(Math.round).join(',') + ')',
      ratio: +ratio(eff, bg).toFixed(2), large: fs >= 24 || (fs >= 18.66 && fw >= 700), hasImg, disabled, code,
      userSelect: s.userSelect || s.webkitUserSelect, ellipsis: s.textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth + 1});
  }
  // fields: font size (iOS zoom under 16px), autocapitalize etc.
  const fields = [...document.querySelectorAll('input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]),textarea,select')].filter(e => vis(e) && shown(e))
    .map(e => ({path: path(e), name: name(e), fs: parseFloat(getComputedStyle(e).fontSize), autocap: e.getAttribute('autocapitalize'), autocorrect: e.getAttribute('autocorrect'),
      spell: e.getAttribute('spellcheck'), hasLabel: !!(e.labels && e.labels.length) || !!e.getAttribute('aria-label') || !!e.getAttribute('aria-labelledby')}));
  const de = document.scrollingElement || document.documentElement;
  const wide = [];
  for (const el of document.querySelectorAll('body *')) { if (!vis(el) || !shown(el)) continue; const r = el.getBoundingClientRect();
    if (r.right > innerWidth + 2 && r.left < innerWidth && !el.closest('#viewer,#stage,#stage2,#layer,table') && getComputedStyle(el).position !== 'fixed') wide.push(path(el) + ' right=' + Math.round(r.right)) }
  return {url: location.pathname + location.search + location.hash, iw: innerWidth, ih: innerHeight,
    hScroll: de.scrollWidth > de.clientWidth + 1, scrollWidth: de.scrollWidth, wide: wide.slice(0, 15),
    targets, overlaps, texts, fields};
})()
