// The equipment list by system, as data: a port of core views.systemsView (core/src/kks/views.nim) for the browser
// client, which builds its own model (index.html). No DOM here: index.html renders it, tests/web/test_systems.py runs
// it against core/tests/test_model.nim's cases.
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

  return {decode, photoCover, photoCovers, systemsView, located, pct, coverageView};
})();
