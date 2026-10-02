// The KKS Explorer internet relay (M5, docs/PROTOCOL.md §18; also protocol v2, docs/PROTOCOL-v2.md §18): a Cloudflare Worker + one Durable Object per plant
// ("room"). The same protocol as peer/relay_server.py. It never sees plant data: devices meet here, prove they hold
// their device key, swap addresses for a direct connection (hole punching), and if that fails get a pipe that passes
// their end-to-end encrypted (Noise) sync bytes along unread.
//   GET /v1/room/<room>                 presence + signaling (JSON text messages)
//   GET /v1/pipe/<room>/<id>/<a|b>      a pipe between the two sides of connection <id> (binary messages)
const ROOM = /^[0-9a-f]{32}$/, PEER = /^[A-Za-z0-9_-]{43}$/, ID = /^[0-9a-f]{32}$/;
// protocol v2 (docs/PROTOCOL-v2.md §18): P-256 device keys, peer ID = base64url of the first 24 bytes of SHA-256(key)
const PEER2 = /^[A-Za-z0-9_-]{32}$/, KEY2 = /^[A-Za-z0-9_-]{87}$/;
const b64uOf = b => btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const MAX_PEERS = 200, PIPE_WAIT_MS = 30000, MAX_BUFFER = 1 << 20;

export default {
  async fetch(req, env) {
    const p = new URL(req.url).pathname.split('/');
    const ok = (p[1] === 'v1' && p[2] === 'room' && p.length === 4 && ROOM.test(p[3])) ||
               (p[1] === 'v1' && p[2] === 'pipe' && p.length === 6 && ROOM.test(p[3]) && ID.test(p[4]) && (p[5] === 'a' || p[5] === 'b'));
    if (!ok) return new Response('KKS Explorer relay\n', {status: 404});
    if (req.headers.get('Upgrade') !== 'websocket') return new Response('expected a WebSocket', {status: 426});
    return env.ROOMS.get(env.ROOMS.idFromName(p[3])).fetch(req);
  },
};

const b64u = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - s.length % 4) % 4)), c => c.charCodeAt(0));
const candOk = c => Array.isArray(c) && c.length <= 8 && c.every(x => typeof x === 'string' && x.length <= 64 && x.includes(':'));

export class Room {
  constructor(ctx, env) {
    this.ctx = ctx;
    // answered without waking the object: keeps idle connections cheap
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}'));
  }

  async fetch(req) {
    const p = new URL(req.url).pathname.split('/');
    const [client, server] = Object.values(new WebSocketPair());
    if (p[2] === 'room') {
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({kind: 'room', room: p[3]});
    } else {
      const [id, side] = [p[4], p[5]];
      if (this.ctx.getWebSockets(`pipe:${id}:${side}`).length) return new Response('taken', {status: 409});
      this.ctx.acceptWebSocket(server, [`pipe:${id}:${side}`]);
      server.serializeAttachment({kind: 'pipe', id, side});
      const other = this.ctx.getWebSockets(`pipe:${id}:${side === 'a' ? 'b' : 'a'}`)[0];
      if (other) {   // the other side was first: hand over what it already sent
        const buf = (await this.ctx.storage.get(`buf:${id}:${side === 'a' ? 'b' : 'a'}`)) || [];
        for (const m of buf) server.send(m);
        await this.ctx.storage.delete(`buf:${id}:${side === 'a' ? 'b' : 'a'}`);
      } else {
        await this.ctx.storage.put(`wait:${id}:${side}`, Date.now() + PIPE_WAIT_MS);
        if (!(await this.ctx.storage.getAlarm())) await this.ctx.storage.setAlarm(Date.now() + PIPE_WAIT_MS);
      }
    }
    return new Response(null, {status: 101, webSocket: client});
  }

  members(except) {   // except: a socket being closed (workerd still lists it while webSocketClose runs)
    const out = new Map();
    for (const ws of this.ctx.getWebSockets()) {
      if (ws === except) continue;
      const a = ws.deserializeAttachment();
      if (a?.kind === 'room' && a.peer) out.set(a.peer, ws);
    }
    return out;
  }

  tell(msg, but, except) {
    const s = JSON.stringify(msg);
    for (const [peer, ws] of this.members(except)) if (peer !== but) try { ws.send(s) } catch (e) {}
  }

  async webSocketMessage(ws, msg) {
    const a = ws.deserializeAttachment();
    if (a.kind === 'pipe') {
      if (typeof msg === 'string') return;
      const other = this.ctx.getWebSockets(`pipe:${a.id}:${a.side === 'a' ? 'b' : 'a'}`)[0];
      if (other) { other.send(msg); return }
      const key = `buf:${a.id}:${a.side}`, buf = (await this.ctx.storage.get(key)) || [];
      if (buf.reduce((n, m) => n + m.byteLength, 0) + msg.byteLength > MAX_BUFFER) { ws.close(1009, 'too much before the other side came'); return }
      buf.push(msg); await this.ctx.storage.put(key, buf);
      return;
    }
    let m; try { m = JSON.parse(typeof msg === 'string' ? msg : new TextDecoder().decode(msg)) } catch (e) { return }
    if (!a.peer) {   // the first message: hello, signed with the device key
      const {peer, ts, sig} = m;
      const v2 = typeof m.key === 'string';
      let ok = m.t === 'hello' && typeof peer === 'string' && (v2 ? PEER2.test(peer) && KEY2.test(m.key) : PEER.test(peer)) &&
               Number.isInteger(ts) && Math.abs(ts - Date.now() / 1000) <= 300 && typeof sig === 'string';
      if (ok) try {
        if (v2) {   // ECDSA P-256 with SHA-256, signature r ‖ s; the peer ID must be the key's
          const raw = b64u(m.key);
          ok = raw.length === 65 && raw[0] === 4 && b64uOf(new Uint8Array(await crypto.subtle.digest('SHA-256', raw)).slice(0, 24)) === peer;
          if (ok) {
            const key = await crypto.subtle.importKey('raw', raw, {name: 'ECDSA', namedCurve: 'P-256'}, false, ['verify']);
            ok = await crypto.subtle.verify({name: 'ECDSA', hash: 'SHA-256'}, key, b64u(sig), new TextEncoder().encode(`kks-relay-hello-v2\n${a.room}\n${ts}`));
          }
        } else {
          const key = await crypto.subtle.importKey('raw', b64u(peer), {name: 'Ed25519'}, false, ['verify']);
          ok = await crypto.subtle.verify({name: 'Ed25519'}, key, b64u(sig), new TextEncoder().encode(`kks-relay-hello-v1\n${a.room}\n${ts}`));
        }
      } catch (e) { ok = false }
      if (!ok) { ws.send(JSON.stringify({t: 'error', why: 'bad hello'})); ws.close(1008, 'bad hello'); return }
      const members = this.members(), old = members.get(peer);
      if (!old && members.size >= MAX_PEERS) { ws.send(JSON.stringify({t: 'error', why: 'room full'})); ws.close(1008, 'room full'); return }
      if (old) { old.serializeAttachment({kind: 'room', room: a.room, replaced: true}); try { old.close(1000, 'replaced') } catch (e) {} }
      ws.serializeAttachment({...a, peer});
      ws.send(JSON.stringify({t: 'welcome', peers: [...members.keys()].filter(p => p !== peer)}));
      this.tell({t: 'joined', peer}, peer);
      return;
    }
    const {t, to, id} = m;
    if (!['connect', 'accept', 'pipe', 'refuse'].includes(t) || typeof to !== 'string' || typeof id !== 'string' || !ID.test(id) ||
        ('cand' in m && !candOk(m.cand))) return;
    const target = this.members().get(to);
    if (target) target.send(JSON.stringify({t, from: a.peer, id, ...('cand' in m ? {cand: m.cand} : {})}));
    else ws.send(JSON.stringify({t: 'gone', id, peer: to}));
  }

  async webSocketClose(ws) { await this.gone(ws) }
  async webSocketError(ws) { await this.gone(ws) }

  async gone(ws) {
    const a = ws.deserializeAttachment() || {};
    if (a.kind === 'room' && a.peer && !a.replaced && !this.members(ws).has(a.peer)) this.tell({t: 'left', peer: a.peer}, null, ws);
    if (a.kind === 'pipe') {
      for (const o of this.ctx.getWebSockets(`pipe:${a.id}:${a.side === 'a' ? 'b' : 'a'}`)) try { o.close(1000, 'the other side left') } catch (e) {}
      await this.ctx.storage.delete([`buf:${a.id}:a`, `buf:${a.id}:b`, `wait:${a.id}:a`, `wait:${a.id}:b`]);
    }
  }

  async alarm() {   // pipes whose other side never came
    const now = Date.now();
    for (const [key, until] of await this.ctx.storage.list({prefix: 'wait:'})) {
      const [, id, side] = key.split(':');
      const paired = this.ctx.getWebSockets(`pipe:${id}:${side === 'a' ? 'b' : 'a'}`).length > 0;
      if (paired || until <= now) {
        if (!paired) for (const ws of this.ctx.getWebSockets(`pipe:${id}:${side}`)) try { ws.close(1000, 'the other side never came') } catch (e) {}
        await this.ctx.storage.delete([key, `buf:${id}:${side}`]);
      }
    }
    const left = await this.ctx.storage.list({prefix: 'wait:'});
    if (left.size) await this.ctx.storage.setAlarm(now + 5000);
  }
}
