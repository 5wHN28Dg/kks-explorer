// Walkdown Plant's multiplayer relay (docs/plant3d/MULTIPLAYER.md §9.1, decision 0068): a Cloudflare Worker with one
// Durable Object per session room. The same protocol as relay-plant/twin.py. It never sees K, P or the invite code:
// a room is admitted by SHA-256(admit), and the packets it passes on are end-to-end encrypted and never read.
//   GET /v1/room/<room>   room = 32 lowercase hex characters; upgrades to a WebSocket
// The first message is text: {"t":"hello","admit":<32 bytes base64url>,"create":true|false}. Then binary messages:
// `to` (2 bytes, big-endian: a relay ID, 0 for every other member) and one or more packets, each a 2-byte big-endian
// length and that many bytes. The relay replaces `to` with the sender's relay ID and passes the message on.
import {DurableObject} from 'cloudflare:workers';

const ROOM = /^[0-9a-f]{32}$/, ADMIT = /^[A-Za-z0-9_-]{43}$/;

// MULTIPLAYER.md §9.1's limits. Only the timings and two counts (rooms a day, joins a minute) can be changed, for the tests against
// `wrangler dev` (`--var RELAY_LIMITS:{...}`): deploy.sh refuses a wrangler.toml that sets any variable.
export const LIMITS = {
  members: 12,            // sockets per room that have said hello
  pending: 12,            // sockets per room still to say hello
  message: 65536,         // bytes per binary message
  text: 512,              // bytes per text message
  rate: 60, hostRate: 120,               // messages a second (token bucket)
  burst: 200, hostBurst: 400,            // the bucket's size
  bytes: 256 * 1024, byteBurst: 1 << 20, // bytes a second, and the bucket's size
  cut: 3,                 // at this many times a rate, kept for `window` ms, the socket is closed (`limit`)
  window: 10000,
  idle: 600000,           // no binary message for this long: the room is closed and deleted
  empty: 600000,          // nobody in it for this long: the same
  maxAge: 86400000,       // a room lives at most this long
  hello: 10000,           // a socket must say hello within this
  failed: 30,             // failed hellos per room per minute; beyond, every hello is refused (`limit`)
  joins: 60,              // successful hellos per room per minute
  daily: 200,             // rooms created per UTC day
};
const TUNABLE = ['idle', 'empty', 'maxAge', 'hello', 'daily', 'joins'];

export function limitsOf(env) {
  const l = {...LIMITS};
  if (typeof env?.RELAY_LIMITS === 'string') {
    try {
      const o = JSON.parse(env.RELAY_LIMITS);
      for (const k of TUNABLE) if (Number.isInteger(o[k]) && o[k] > 0) l[k] = o[k];
    } catch (e) {}
  }
  return l;
}

export default {
  async fetch(req, env) {
    const p = new URL(req.url).pathname.split('/');
    if (!(p.length === 4 && p[1] === 'v1' && p[2] === 'room' && ROOM.test(p[3])))
      return new Response('Walkdown Plant relay\n', {status: 404});
    if (req.method !== 'GET' || req.headers.get('Upgrade')?.toLowerCase() !== 'websocket')
      return new Response('expected a WebSocket', {status: 426});
    return env.ROOMS.get(env.ROOMS.idFromName(p[3])).fetch(req);
  },
};

const b64u = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - s.length % 4) % 4)), c => c.charCodeAt(0));
const sha256 = async b => new Uint8Array(await crypto.subtle.digest('SHA-256', b));
const same = (a, b) => {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
};
const ID_BLOCK = 16;   // relay IDs are reserved in storage this many at a time (one row write per 16 joins)

// One token bucket: `rate` a second, at most `size` kept.
class Bucket {
  constructor(rate, size, now) { this.rate = rate; this.size = size; this.v = size; this.at = now }
  take(n, now, rate, size) {
    this.rate = rate; this.size = size;
    this.v = Math.min(this.size, this.v + (now - this.at) * this.rate / 1000); this.at = now;
    if (this.v < n) return false;
    this.v -= n; return true;
  }
}

// What a socket sent in the last `window` ms, in 1 s slots: for closing a socket far over its limit.
class Window {
  constructor() { this.slots = new Map() }
  add(now, msgs, bytes, window) {
    const s = Math.floor(now / 1000);
    const cur = this.slots.get(s) || [0, 0];
    cur[0] += msgs; cur[1] += bytes; this.slots.set(s, cur);
    let m = 0, b = 0;
    for (const [k, v] of this.slots) {
      if (k <= s - window / 1000) this.slots.delete(k);
      else { m += v[0]; b += v[1] }
    }
    return [m, b];
  }
}

export class Room extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
    this.L = limitsOf(env);
    // answered without waking the object, so a paused room hibernates (as Walkdown's relay does)
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}'));
    this.flow = new Map();      // relay ID -> {msgs, bytes, win, slowAt}: in memory only, as §9.1 says
    this.failed = [];           // times of failed hellos (the last minute)
    this.joined = [];           // times of successful hellos (the last minute)
    this.lastBinary = 0;        // also kept in each sender's attachment (`lb`), which survives hibernation
    this.nextId = 0;            // the next relay ID; 0: read the reserved floor from storage first
    this.idCeil = 0;
  }

  // ---------- storage: one row per room ----------
  row() {
    const t = this.ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'room'").toArray();
    if (!t.length) return null;
    return this.ctx.storage.sql.exec('SELECT admit, created, id_floor, empty_since FROM room').toArray()[0] || null;
  }

  sockets(except) { return this.ctx.getWebSockets().filter(ws => ws !== except) }
  members(except) {
    const out = [];
    for (const ws of this.sockets(except)) {
      const a = ws.deserializeAttachment();
      if (a?.id && !a.gone) out.push([a, ws]);
    }
    return out;
  }

  send(ws, obj) { try { ws.send(JSON.stringify(obj)) } catch (e) {} }
  // an error, then the socket is closed; a member that is closed (`limit`) leaves as if it had closed itself
  refuse(ws, why) {
    this.send(ws, {t: 'error', why});
    return this.gone(ws, 1008, why);
  }
  tell(obj, except) { const s = JSON.stringify(obj); for (const [, ws] of this.members(except)) try { ws.send(s) } catch (e) {} }

  async fetch(req) {
    const now = Date.now();
    // sockets that never said hello in time go first: they don't keep a stranger's place
    let pending = 0;
    for (const ws of this.sockets()) {
      const a = ws.deserializeAttachment();
      if (a && !a.id && !a.gone) {
        if (now - a.at > this.L.hello) this.refuse(ws, 'no hello');
        else pending++;
      }
    }
    if (pending >= this.L.pending) return new Response('too many waiting', {status: 429});
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({at: now, ip: req.headers.get('CF-Connecting-IP') || ''});
    setTimeout(() => {
      const a = server.deserializeAttachment();
      if (a && !a.id && !a.gone) this.refuse(server, 'no hello');
    }, this.L.hello);
    return new Response(null, {status: 101, webSocket: client});
  }

  async webSocketMessage(ws, msg) {
    const a = ws.deserializeAttachment();
    if (!a || a.gone) return;
    if (!a.id) return this.hello(ws, a, msg);
    const now = Date.now(), size = typeof msg === 'string' ? new TextEncoder().encode(msg).length : msg.byteLength;
    if (!this.admitFlow(ws, a, size, now)) return;
    if (typeof msg === 'string') {
      if (size > this.L.text) return;
      let m; try { m = JSON.parse(msg) } catch (e) { return }
      if (m?.t === 'ping') { this.send(ws, {t: 'pong'}); return }
      if (m?.t === 'host') this.claimHost(ws, a);
      return;
    }
    this.forward(ws, a, new Uint8Array(msg), now);
  }

  // the per-socket limits: false when the message is dropped (or the socket closed)
  admitFlow(ws, a, size, now) {
    const host = !!a.host, L = this.L;
    let f = this.flow.get(a.id);
    if (!f) this.flow.set(a.id, f = {msgs: new Bucket(L.rate, L.burst, now), bytes: new Bucket(L.bytes, L.byteBurst, now), win: new Window(), slowAt: 0});
    const rate = host ? L.hostRate : L.rate;
    const [m, b] = f.win.add(now, 1, size, L.window);
    if (m > L.cut * rate * L.window / 1000 || b > L.cut * L.bytes * L.window / 1000) {
      this.refuse(ws, 'limit');
      return false;
    }
    if (size > L.message || !f.msgs.take(1, now, rate, host ? L.hostBurst : L.burst) || !f.bytes.take(size, now, L.bytes, L.byteBurst)) {
      if (now - f.slowAt >= 1000) { f.slowAt = now; this.send(ws, {t: 'slow'}) }
      return false;
    }
    return true;
  }

  async hello(ws, a, msg) {
    const now = Date.now(), L = this.L;
    this.failed = this.failed.filter(t => now - t < 60000);
    this.joined = this.joined.filter(t => now - t < 60000);
    if (this.failed.length >= L.failed) return this.refuse(ws, 'limit');
    const fail = why => { this.failed.push(now); this.refuse(ws, why) };
    if (typeof msg !== 'string' || new TextEncoder().encode(msg).length > L.text) return fail('bad hello');
    let m; try { m = JSON.parse(msg) } catch (e) { return fail('bad hello') }
    if (!m || typeof m !== 'object' || Array.isArray(m) || m.t !== 'hello' || typeof m.admit !== 'string' ||
        !ADMIT.test(m.admit) || typeof m.create !== 'boolean' || Object.keys(m).length !== 3) return fail('bad hello');
    const raw = b64u(m.admit);
    if (raw.length !== 32) return fail('bad hello');
    const hash = await sha256(raw);
    // (an await above: the room may have changed meanwhile; everything below up to the next await is one step)
    if (m.create) {
      if (this.row()) return this.refuse(ws, 'exists');
      if (!(await this.mayCreate(a.ip, now))) return this.refuse(ws, 'limit');
      if (ws.deserializeAttachment()?.gone) return;
      if (this.row()) return this.refuse(ws, 'exists');   // another create won while this one asked
      const sql = this.ctx.storage.sql;
      sql.exec('CREATE TABLE IF NOT EXISTS room (admit BLOB NOT NULL, created INTEGER NOT NULL, id_floor INTEGER NOT NULL, empty_since INTEGER)');
      sql.exec('INSERT INTO room (admit, created, id_floor, empty_since) VALUES (?, ?, ?, NULL)', hash.buffer, now, 1 + ID_BLOCK);
      this.nextId = 1; this.idCeil = 1 + ID_BLOCK; this.lastBinary = 0;
      this.admit(ws, a, now, true);   // before the next await: the creator is relay ID 1
      await this.ctx.storage.setAlarm(now + Math.min(L.idle, L.empty, L.maxAge));
      return;
    }
    const row = this.row();
    if (!row || now - row.created >= L.maxAge) return fail('no such session');
    if (!same(new Uint8Array(row.admit), hash)) return fail('bad admit');
    const members = this.members(ws);
    if (members.length >= L.members) return this.refuse(ws, 'full');
    if (this.joined.length >= L.joins) return this.refuse(ws, 'limit');
    if (!this.nextId) { this.nextId = row.id_floor; this.idCeil = row.id_floor }
    if (this.nextId > 65535) return this.refuse(ws, 'full');
    if (this.nextId >= this.idCeil) {   // reserve the next block before handing out any of it
      this.idCeil = Math.min(this.nextId + ID_BLOCK, 65536);
      this.ctx.storage.sql.exec('UPDATE room SET id_floor = ?', this.idCeil);
    }
    return this.admit(ws, a, now, false);
  }

  admit(ws, a, now, creator) {
    const id = this.nextId++, others = this.members(ws);
    this.joined.push(now);
    ws.serializeAttachment({...a, id, host: creator, lb: 0});
    const host = others.find(([o]) => o.host);
    this.send(ws, {t: 'welcome', id, peers: others.map(([o]) => o.id), host: creator ? id : host ? host[0].id : null});
    this.tell({t: 'joined', id}, ws);
  }

  claimHost(ws, a) {
    if (a.host) return;
    for (const [o, other] of this.members(ws)) if (o.host) other.serializeAttachment({...o, host: false});
    ws.serializeAttachment({...a, host: true});
    this.tell({t: 'host', id: a.id});
  }

  forward(ws, a, b, now) {
    // framing: `to`, then packets of 2-byte length; anything else is dropped unread
    if (b.length < 5) return;
    let i = 2;
    while (i < b.length) {
      if (i + 2 > b.length) return;
      const n = (b[i] << 8) | b[i + 1];
      if (n === 0 || i + 2 + n > b.length) return;
      i += 2 + n;
    }
    const to = (b[0] << 8) | b[1];
    if (to === a.id) return;
    this.lastBinary = now;
    if (!a.lb || now - a.lb >= 1000) ws.serializeAttachment({...a, lb: now});
    const out = b.slice();
    out[0] = a.id >> 8; out[1] = a.id & 255;
    for (const [o, other] of this.members(ws)) {
      if (to === 0 || o.id === to) try { other.send(out) } catch (e) {}
    }
  }

  async mayCreate(ip, now) {
    // the Workers rate limiting binding (per Cloudflare location, approximate): 10 rooms a minute per address
    if (this.env.CREATE_LIMIT && ip) {
      try { if (!(await this.env.CREATE_LIMIT.limit({key: ip})).success) return false } catch (e) {}
    }
    // and at most `daily` rooms per UTC day, counted by one Durable Object
    const day = new Date(now).toISOString().slice(0, 10);
    return await this.env.DAILY.get(this.env.DAILY.idFromName('rooms')).take(day, this.L.daily);
  }

  async webSocketClose(ws) { await this.gone(ws) }
  async webSocketError(ws) { await this.gone(ws) }

  async gone(ws, code = 1000, reason = 'bye') {
    const a = ws.deserializeAttachment();
    if (!a || a.gone) return;
    ws.serializeAttachment({...a, gone: true});
    try { ws.close(code, reason) } catch (e) {}
    if (!a.id) return;
    this.flow.delete(a.id);
    const rest = this.members(ws);
    // the leaver's last binary time stays in the room (hibernation keeps only the attachments)
    if (a.lb && rest.length) {
      const [o, other] = rest[0];
      if (!o.lb || o.lb < a.lb) other.serializeAttachment({...o, lb: a.lb});
    }
    this.tell({t: 'left', id: a.id}, ws);
    if (!rest.length && this.row()) {
      const now = Date.now();
      this.ctx.storage.sql.exec('UPDATE room SET empty_since = ?', now);
      const due = await this.ctx.storage.getAlarm();
      if (!due || due > now + this.L.empty) await this.ctx.storage.setAlarm(now + this.L.empty);
    }
  }

  async alarm() {
    const now = Date.now(), L = this.L, row = this.row();
    if (!row) { await this.ctx.storage.deleteAll(); return }
    const members = this.members();
    let due = row.created + L.maxAge;
    if (members.length) {
      let last = Math.max(row.created, this.lastBinary);
      for (const [o] of members) if (o.lb) last = Math.max(last, o.lb);
      due = Math.min(due, last + L.idle);
    } else {
      due = Math.min(due, (row.empty_since ?? row.created) + L.empty);
    }
    if (now < due) { await this.ctx.storage.setAlarm(due); return }
    const why = now >= row.created + L.maxAge ? 'expired' : 'idle';
    for (const ws of this.sockets()) {
      const a = ws.deserializeAttachment();
      if (a) ws.serializeAttachment({...a, gone: true});
      this.send(ws, {t: 'error', why});
      try { ws.close(1000, why) } catch (e) {}
    }
    this.flow.clear(); this.nextId = 0; this.idCeil = 0; this.lastBinary = 0;
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }
}

// Rooms created per UTC day (one object for the whole relay; one request per room created).
export class Daily extends DurableObject {
  take(day, max) {
    const sql = this.ctx.storage.sql;
    sql.exec('CREATE TABLE IF NOT EXISTS days (day TEXT PRIMARY KEY, n INTEGER NOT NULL)');
    sql.exec('DELETE FROM days WHERE day <> ?', day);
    const n = sql.exec('SELECT n FROM days WHERE day = ?', day).toArray()[0]?.n ?? 0;
    if (n >= max) return false;
    sql.exec('INSERT INTO days (day, n) VALUES (?, ?) ON CONFLICT (day) DO UPDATE SET n = excluded.n', day, n + 1);
    return true;
  }
}
