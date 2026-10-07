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
    const item = k => {
      const it = items.get(k);
      return {code: k, tag: it.tag, sheet: it.sheet, sheet_name: sheetName.has(it.sheet) ? sheetName.get(it.sheet) : it.sheet,
              desc: it.desc, count: it.count, photos: photoCover(k, photos)};
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

  return {decode, photoCover, systemsView};
})();
