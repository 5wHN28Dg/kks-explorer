// The equipment list by system, a tag's valve type and the links between drawings, as data: ports of core
// views.systemsView, model.valveTypeOf and views.linksView (core/src/kks/views.nim, model.nim) for the browser client,
// which builds its own model (index.html). No DOM here: index.html renders them; tests/web/test_systems.py and
// test_links.py run them against the core's cases and vectors.
'use strict';
const KSys = (() => {
  const cmp = (a, b) => a < b ? -1 : a > b ? 1 : 0;   // Nim's sort on strings: byte order (the codes are ASCII)
  const lower = s => s.replace(/[A-Z]/g, c => c.toLowerCase());   // Nim's toLowerAscii
  const words = q => lower(q).split(/[ \t\v\r\n\f]+/).filter(Boolean);   // Nim's splitWhitespace
  const name = (tables, which, k) => (tables && tables[which] && typeof tables[which][k] === 'string') ? tables[which][k] : '';

  // KKS → its parts (core model.decode); null when the code isn't a full equipment code
  function decode(t, tables) {
    const m = (t.kks || '').match(/^(\d{2})([A-Z]{3})(\d{2})([A-Z]{2})(\d{3})$/); if (!m) return null;
    const [, blk, sys, fn, comp, num] = m;
    let isa = '';
    if (t.isa) {
      const first = t.isa.startsWith('PD') ? 'PD' : t.isa[0], rest = t.isa.slice(first.length);
      isa = (name(tables, 'isa_first', first) || first) + ' — ' + [...rest].map(c => name(tables, 'isa_next', c) || c).join(', ');
    }
    return {blk, sys, fn, comp, num, isa};
  }

  // which photos a code has: "both", "equipment", "plate" or "none" (core model.photoCover; a photo of the tag plate is
  // one whose caption starts with "Tag plate", PROTOCOL-v2 §9)
  function photoCover(k, photos) {
    if (!k) return 'none';
    let e = false, p = false;
    for (const x of photos || []) if (x.kks === k) { if ((x.caption || '').startsWith('Tag plate')) p = true; else e = true }
    return e && p ? 'both' : e ? 'equipment' : p ? 'plate' : 'none';
  }

  // photoCover for every code, in one pass (core model.photoCovers): a code missing here has "none"
  function photoCovers(photos) {
    const e = new Set(), p = new Set(), out = new Map();
    for (const x of photos || []) if (x.kks) ((x.caption || '').startsWith('Tag plate') ? p : e).add(x.kks);
    for (const k of e) out.set(k, p.has(k) ? 'both' : 'equipment');
    for (const k of p) if (!e.has(k)) out.set(k, 'plate');
    return out;
  }

  // Every code on the drawings once, grouped block → system → subsystem (the system number, e.g. LAB 70) → component
  // kind, each opening the first tag that shows it. `q` keeps the codes whose code, names, subsystem, ISA words or
  // location-list description contain every word of it. Codes that don't decode are listed under `other`.
  //   tags: the effective tags (review decisions applied, rejected ones left out), in the page's order
  //   sheets: [{id, name}]; kks: data/kks.json; loc: the location list by KKS without the unit; photos: state photos
  // -> {blocks: [{blk, blk_name, systems: [{sys, sys_name, count, subsystems: [{fn, code, count, kinds: [{comp,
  //    comp_name, count, items}]}]}]}], other: [item], total}; item = {code, tag, sheet, sheet_name, desc, count, photos}
  function systemsView({tags, sheets, kks, loc, photos}, q = '') {
    const items = new Map(), dec = new Map(), other = [];
    for (const t of tags) {
      if (!t.kks) continue;
      const k = t.kks + (t.suffix || '');
      const have = items.get(k);
      if (have) { have.count++; continue }
      let desc = '';
      for (const r of (loc && loc[t.kks.slice(2)]) || []) if (typeof r.desc === 'string' && r.desc.length) { desc = r.desc; break }
      items.set(k, {code: k, tag: t.id, sheet: t.sheet, desc, count: 1});
      const d = decode(t, kks);
      if (d) dec.set(k, d); else other.push(k);
    }
    const ws = words(q);
    const keep = k => {
      if (!ws.length) return true;
      let hay = k + ' ' + items.get(k).desc;
      const d = dec.get(k);
      if (d) hay += ' ' + d.blk + ' ' + name(kks, 'blocks', d.blk) + ' ' + d.sys + ' ' + name(kks, 'systems', d.sys) + ' ' +
                    d.sys + d.fn + ' ' + d.comp + ' ' + name(kks, 'components', d.comp) + ' ' + d.isa;
      hay = lower(hay);
      return ws.every(w => hay.includes(w));
    };
    const sheetName = new Map((sheets || []).map(s => [s.id, s.name]));
    const covers = photoCovers(photos);
    const item = k => {
      const it = items.get(k);
      return {code: k, tag: it.tag, sheet: it.sheet, sheet_name: sheetName.has(it.sheet) ? sheetName.get(it.sheet) : it.sheet,
              desc: it.desc, count: it.count, photos: covers.get(k) || 'none'};
    };
    // block → system → subsystem → kind → codes, every level sorted by its code
    const tree = new Map(), at = (m, k) => { let v = m.get(k); if (!v) m.set(k, v = new Map()); return v };
    let total = 0;
    for (const [k, d] of dec) {
      if (!keep(k)) continue;
      total++;
      const kinds = at(at(at(tree, d.blk), d.sys), d.fn);
      (kinds.get(d.comp) || kinds.set(d.comp, []).get(d.comp)).push(k);
    }
    const sorted = m => [...m.keys()].sort(cmp);
    const blocks = sorted(tree).map(b => ({blk: b, blk_name: name(kks, 'blocks', b), systems: sorted(tree.get(b)).map(s => {
      let sysCount = 0;
      const subsystems = sorted(tree.get(b).get(s)).map(f => {
        let subCount = 0;
        const kinds = sorted(tree.get(b).get(s).get(f)).map(c => {
          const codes = [...tree.get(b).get(s).get(f).get(c)].sort(cmp);
          subCount += codes.length;
          return {comp: c, comp_name: name(kks, 'components', c), count: codes.length, items: codes.map(item)};
        });
        sysCount += subCount;
        return {fn: f, code: s + f, count: subCount, kinds};
      });
      return {sys: s, sys_name: name(kks, 'systems', s), count: sysCount, subsystems};
    })}));
    const rest = [];
    for (const k of other.sort(cmp)) if (keep(k)) { total++; rest.push(item(k)) }
    return {blocks, other: rest, total};
  }

  // a place is known (core views.located): the location list has the code (by KKS without the unit), or a person filled
  // one of the place fields (Nim's strip: only ASCII whitespace counts as empty)
  const own = (o, k) => o != null && typeof o === 'object' && Object.prototype.hasOwnProperty.call(o, k) ? o[k] : undefined;
  const PLACE = ['area', 'floor', 'elev', 'near', 'loc'];
  function located(t, loc, equipment) {
    const body = (t.kks || '').length > 2 ? t.kks.slice(2) : '';
    const rows = own(loc, body);
    if (Array.isArray(rows) && rows.length) return true;
    const e = own(equipment, (t.kks || '') + (t.suffix || ''));
    return PLACE.some(f => { const v = own(e, f); return typeof v === 'string' && /[^ \t\v\r\n\f]/.test(v) });
  }

  // a of b (b > 0) as a whole percent (core views.coveragePct): to the nearest, but 100 only when all and 0 only when
  // none (199 of 200 = 99, 1 of 300 = 1)
  function pct(a, b) {
    if (a <= 0) return 0;
    if (a >= b) return 100;
    return Math.min(99, Math.max(1, Math.floor((200 * a + b) / (2 * b))));
  }

  // How complete the plant's record is (core views.coverageView): totals, per sheet (the page's sheets first, in their
  // order) and per system (sorted; "" = codes that don't decode). Codes are counted once per sheet, per system and in
  // the totals; tags, review and marked are per tag, so system rows don't have them.
  //   tags: the effective tags as for systemsView; sheets: [{id, name}]; kks: data/kks.json; loc: the location list by
  //   KKS without the unit; equipment: state equipment (by full code); photos: state photos
  // -> {total: counts, sheets: [counts + {id, name}], systems: [{sys, sys_name, codes, verified, located, photos}]};
  //    counts = {tags, verified, review, marked, codes, located, photos: {both, equipment, plate, none}}
  function coverageView({tags, sheets, kks, loc, equipment, photos}) {
    const pcs = () => ({both: 0, equipment: 0, plate: 0, none: 0});
    const blank = () => ({tags: 0, verified: 0, review: 0, marked: 0, codes: 0, located: 0, photos: pcs()});
    const covers = photoCovers(photos);
    const bySheet = new Map(), bySys = new Map(), seenSheet = new Map(), seenSys = new Set(), seenAll = new Set();
    for (const s of sheets || []) bySheet.set(s.id, blank());
    const all = blank();
    const checked = t => t.status === 'verified' || t.status === 'confirmed';
    // a code is checked when a person checked any of its tags (as the core: auto on one sheet, verified on another)
    const checkedCodes = new Set(tags.filter(t => t.kks && checked(t)).map(t => t.kks + (t.suffix || '')));
    // located once per (unit-less body, code), as the core: the code alone can't key it (a suffix typed into the code)
    const placed = new Map();
    const isLocated = t => {
      const key = JSON.stringify([t.kks || '', t.suffix || '']);
      if (!placed.has(key)) placed.set(key, located(t, loc, equipment));
      return placed.get(key);
    };
    for (const t of tags) {
      if (!bySheet.has(t.sheet)) bySheet.set(t.sheet, blank());
      const c = bySheet.get(t.sheet);
      c.tags++; all.tags++;
      if (checked(t)) { c.verified++; all.verified++ }
      if (t.status === 'review') { c.review++; all.review++ }
      if (t.added) { c.marked++; all.marked++ }
      if (!t.kks) continue;
      const k = t.kks + (t.suffix || ''), p = covers.get(k) || 'none';
      let seen = seenSheet.get(t.sheet);
      if (!seen) seenSheet.set(t.sheet, seen = new Set());
      if (!seen.has(k)) { seen.add(k); c.codes++; c.photos[p]++; if (isLocated(t)) c.located++ }
      if (!seenAll.has(k)) { seenAll.add(k); all.codes++; all.photos[p]++; if (isLocated(t)) all.located++ }
      if (!seenSys.has(k)) {
        seenSys.add(k);
        const d = decode(t, kks), sys = d ? d.sys : '';
        let s = bySys.get(sys);
        if (!s) bySys.set(sys, s = {codes: 0, verified: 0, located: 0, photos: pcs()});
        s.codes++; s.photos[p]++;
        if (isLocated(t)) s.located++;
        if (checkedCodes.has(k)) s.verified++;
      }
    }
    const sheetName = new Map((sheets || []).map(s => [s.id, typeof s.name === 'string' ? s.name : '']));
    return {
      total: all,
      sheets: [...bySheet].map(([id, c]) => ({...c, id, name: sheetName.has(id) ? sheetName.get(id) : id})),
      systems: [...bySys.keys()].sort(cmp).map(k => ({sys: k, sys_name: k ? name(kks, 'systems', k) : '', ...bySys.get(k)})),
    };
  }

  // ---- the valve type (a port of core model.drawnValveType / valveTypeOf and tagView's valve_type) ----
  const VALVE_KEY = 'Valve type';   // the equipment custom field ({k, v}) a confirmed or corrected type is kept in
  const CUSTOM_MAX = 100;           // custom fields per equipment (PROTOCOL-v2: `custom` is a list of at most 100)
  const finite = n => typeof n === 'number' && Number.isFinite(n);   // JSON.parse turns 1e999 into Infinity
  const utf8len = s => new TextEncoder().encode(s).length;
  // tags.json "symbol" as the core keeps it (model.parseTags): an object whose type is a string of 1–100 bytes
  const symbolOf = t => { const y = t && t.symbol;
    return y && typeof y === 'object' && !Array.isArray(y) && typeof y.type === 'string' && utf8len(y.type) >= 1 &&
      utf8len(y.type) <= 100 ? y : null };
  const str = (o, k) => o && typeof o[k] === 'string' ? o[k] : '';
  // the drawn valve symbol in words ("gate valve, motor-operated, normally closed"); '' = none. `nc` = the body is
  // hatched, which on these drawings means normally closed
  function drawnValveType(t) {
    const y = symbolOf(t); if (!y) return '';
    let r = y.type;
    if (str(y, 'actuator') === 'motor') r += ', motor-operated';
    if (y.nc === true) r += ', normally closed';
    return r;
  }
  function customValue(e, key) {
    for (const x of Array.isArray(e && e.custom) ? e.custom : [])
      if (x && typeof x === 'object' && !Array.isArray(x) && str(x, 'k') === key && str(x, 'v').length) return x.v;
    return '';
  }
  // What the panel shows of a tag's valve type, or null: confirmed (the custom field "Valve type") or from the drawing,
  // unchecked, with `confirm`: the equipment proposal that saves it (send it as it is, or with the value edited: a
  // correction; see withValveType). `box`: the symbol's box in the tag's own units (level-0 px), to highlight it.
  //   t: the effective tag; equipment: the live equipment record of its code (STATE.equipment[code])
  function valveType(t, equipment) {
    const k = (t.kks || '') + (t.suffix || ''), drawn = drawnValveType(t), eq = equipment || {};
    const have = k ? customValue(eq, VALVE_KEY) : '';
    if (have) return {status: 'confirmed', text: have, drawn, label: 'confirmed', line: 'Valve type: ' + have + ' (confirmed)',
                      drawn_differs: !!drawn && drawn !== have};
    if (!drawn || !k) return null;
    // the symbol belongs to the code the reader saw: a review that made it a non-valve (component not AA) drops it
    if (!((t.kks || '').length === 12 && t.kks.slice(7, 9) === 'AA')) return null;
    const base = Array.isArray(eq.custom) ? eq.custom.slice() : [];
    // an empty "Valve type" entry already there is replaced, never doubled; a full list can't take one more
    const isKey = x => x && typeof x === 'object' && !Array.isArray(x) && str(x, 'k') === VALVE_KEY;
    const changed = []; let placed = false;
    for (const x of base) {
      if (!placed && isKey(x)) { changed.push({k: VALVE_KEY, v: drawn}); placed = true }
      else if (!isKey(x)) changed.push(x);
    }
    if (!placed) changed.push({k: VALVE_KEY, v: drawn});
    const y = symbolOf(t);
    const r = {status: 'drawing', text: drawn, conf: finite(y.conf) ? y.conf : null, label: 'from the drawing, unchecked',
               line: 'Valve type: ' + drawn + ' (from the drawing, unchecked)', confirm: null};
    if (changed.length <= CUSTOM_MAX)
      r.confirm = {kind: 'equipment', payload: {kks: k, changes: {custom: changed}, base: {custom: base}}};
    const b = y.bbox;
    if (Array.isArray(b) && b.length === 4 && b.every(finite)) r.box = b.slice();
    return r;
  }
  // the confirm proposal with the person's own value instead of the drawing's (a correction); null for an empty value
  function withValveType(confirm, value) {
    const v = String(value || '').trim(); if (!v || !confirm) return null;
    const c = JSON.parse(JSON.stringify(confirm));
    for (const x of c.payload.changes.custom) if (x && typeof x === 'object' && x.k === VALVE_KEY) x.v = v;
    return c;
  }

  // ---- links between drawings (a port of core model.parseSheets' "links" and views.linksView / findLink) ----
  const MAX_LINKS_PER_SHEET = 500, MAX_LINK_LABEL = 16, MAX_LINK_SIDE = 100, MAX_TARGET_NAME = 200, MAX_LINK_TARGETS = 20;
  const num = (o, k, d) => o && typeof o === 'object' && typeof o[k] === 'number' ? o[k] : d;
  const scaleOf = x => num(x, 'scale', 2.0);
  // finite, ordered, at most MAX_LINK_SIDE points across, finite in points (core linkBoxOk)
  function linkBoxOk(b, scale) {
    const sc = scale > 0 ? scale : 2.0;
    for (const v of b) if (!Number.isFinite(v) || !Number.isFinite(v / sc)) return false;
    return b[2] > b[0] && b[3] > b[1] && (b[2] - b[0]) / sc <= MAX_LINK_SIDE && (b[3] - b[1]) / sc <= MAX_LINK_SIDE;
  }
  // a sheets.json entry's connectors as the core keeps them: [{label, bbox, conf}] (bbox in level-0 px)
  function sheetLinks(x) {
    const out = [], ls = x && typeof x === 'object' ? x.links : null;
    if (!Array.isArray(ls)) return out;
    for (const l of ls) {
      if (out.length >= MAX_LINKS_PER_SHEET) break;
      const ok = l && typeof l === 'object' && !Array.isArray(l);
      const label = ok ? str(l, 'label') : '', b = ok ? l.bbox : null;
      if (!ok || !label || utf8len(label) > MAX_LINK_LABEL || !Array.isArray(b) || b.length !== 4) continue;
      if (!b.every(v => typeof v === 'number')) continue;
      // a conf JSON.parse made Infinity (1e999) is taken as read, like the core
      if (linkBoxOk(b, scaleOf(x))) out.push({label, bbox: b.slice(), conf: Number.isFinite(l.conf) ? l.conf : 1.0});
    }
    return out;
  }
  // at most n bytes of UTF-8, cut at a character boundary (core views.clip)
  function clip(s, n) {
    const e = new TextEncoder().encode(s); if (e.length <= n) return s;
    let k = n; while (k > 0 && (e[k] & 0xC0) === 0x80) k--;
    return new TextDecoder().decode(e.subarray(0, k));
  }
  // The sheet's off-page connectors (boxes in points), each with where its line continues: the same label on the other
  // sheets (in the sheets' order), then any other connector with that label on this sheet (same_sheet). No targets =
  // the other end isn't on any sheet we have. -> [{label, conf, x0, y0, x1, y1, targets: [{sheet, sheet_name,
  // same_sheet, x0, y0, x1, y1}]}]
  function linksView(sheets, sheet) {
    const all = (sheets || []).map(x => ({id: str(x, 'id'), name: str(x, 'name'), scale: scaleOf(x), links: sheetLinks(x)}));
    const si = all.find(x => x.id === sheet); if (!si) return [];
    const box = (b, sc) => ({x0: b[0] / sc, y0: b[1] / sc, x1: b[2] / sc, y1: b[3] / sc});
    const byLabel = new Map();
    all.forEach((o, k) => o.links.forEach((x, j) => { if (!byLabel.has(x.label)) byLabel.set(x.label, []); byLabel.get(x.label).push([k, j]) }));
    const s = si.scale > 0 ? si.scale : 2.0;
    return si.links.map((l, i) => {
      const targets = [], same = byLabel.get(l.label) || [];
      fill: for (let pass = 0; pass <= 1; pass++)
        for (const [k, j] of same) {
          const o = all[k];
          if ((pass === 0) === (o.id === sheet) || (o.id === sheet && j === i)) continue;
          if (targets.length >= MAX_LINK_TARGETS) break fill;
          const os = o.scale > 0 ? o.scale : 2.0;
          targets.push({sheet: o.id, sheet_name: clip(o.name, MAX_TARGET_NAME), same_sheet: o.id === sheet, ...box(o.links[j].bbox, os)});
        }
      return {label: l.label, conf: l.conf, ...box(l.bbox, s), targets};
    });
  }
  // the index of the connector with this label and box corner, -1 if it's gone (core findLink)
  function findLink(ls, label, x0, y0) {
    return ls.findIndex(l => l.label === label && Math.abs(l.x0 - x0) < 0.01 && Math.abs(l.y0 - y0) < 0.01);
  }

  return {decode, photoCover, photoCovers, systemsView, located, pct, coverageView, valveType, withValveType, VALVE_KEY, linksView, findLink};
})();
