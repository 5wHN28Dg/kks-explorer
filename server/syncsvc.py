"""Sync as a background service: the listener other devices connect to, finding devices on the same Wi-Fi (mDNS /
DNS-SD service `_kks._tcp`, needs the `zeroconf` package; without it only syncing by address works), automatic syncs
every `sync_interval` seconds and a few seconds after each local change, and a status list for the UI."""
import socket, threading, time

from peer import sync as S

SERVICE = '_kks._tcp.local.'
AFTER_CHANGE = 5          # seconds: a burst of edits becomes one sync


class SyncService:
    def __init__(self, E, cfg, log=print):
        self.E, self.cfg, self.log = E, cfg, log
        self.peers = {}               # mDNS name → {'host', 'port', 'root', 'peer'}
        self.status = {}              # peer ID → {'label', 'address', 'at', 'ok', 'result' | 'error', 'direction'}
        self.lock = threading.Lock()
        self.wake = threading.Event()
        self.zc = self.info = None
        self.announced = None         # (peer, root) last announced; re-announced when either changes
        self.announce_lock = threading.Lock()
        self.discovery = 'off'
        self.srv = None
        self._due = time.time() + 2
        E.listeners.append(self._on_change)

    # ---------- listener ----------
    def listen(self, host, port, max_sessions=8):
        self.srv = socket.create_server((host, port))
        self.port = self.srv.getsockname()[1]
        slots = threading.BoundedSemaphore(max_sessions)

        def one(sock, addr):
            try:
                remote, st = S.serve_one(self.E, sock)
                self._record(remote, f'{addr[0]}', True, st, 'in')
            except (S.SyncError, OSError, Exception) as e:
                self._record(None, addr[0], False, str(e), 'in')
            finally:
                slots.release()

        def loop():
            while True:
                try:
                    sock, addr = self.srv.accept()
                except OSError:
                    return
                if not slots.acquire(blocking=False):
                    sock.close()
                    continue
                threading.Thread(target=one, args=(sock, addr), daemon=True).start()
        threading.Thread(target=loop, daemon=True).start()
        self.log(f'  Sync: listening on {host}:{self.port}')
        return self.port

    # ---------- discovery ----------
    def start_discovery(self):
        if not self.cfg.get('discovery'):
            self.discovery = 'turned off in config'
            return
        try:
            from zeroconf import ServiceBrowser, ServiceInfo, Zeroconf
        except ImportError:
            self.discovery = 'unavailable (the zeroconf package is not installed; sync by address still works)'
            return
        self.zc = Zeroconf()
        self._ServiceInfo = ServiceInfo
        self._advertise()
        svc = self

        class Handler:
            def add_service(self, zc, type_, name):
                threading.Thread(target=svc._resolve, args=(name,), daemon=True).start()
            update_service = add_service

            def remove_service(self, zc, type_, name):
                with svc.lock:
                    svc.peers.pop(name, None)
        self.browser = ServiceBrowser(self.zc, SERVICE, Handler())
        self.discovery = 'on'
        threading.Thread(target=self._auto, daemon=True).start()

    def _advertise(self):
        """(Re)announce this device: its peer ID and the start of its plant's root, so others skip other plants."""
        if not self.zc:
            return
        with self.announce_lock:   # two at once would register the name twice ("... (2)")
            self._advertise_locked()

    def _advertise_locked(self):
        try:
            me = __import__('peer.proto', fromlist=['peer_id']).peer_id(self.E.identity())
        except Exception:
            return
        if (me, self.E.anchor) == self.announced:
            return
        props = {'peer': me, 'root': (self.E.anchor or '')[:16], 'v': '1'}
        info = self._ServiceInfo(SERVICE, f'kks-{me[:12]}.{SERVICE}', port=self.port,
                                 addresses=[socket.inet_aton(ip) for ip in _lan_ips()], properties=props)
        try:
            if self.info:
                self.zc.unregister_service(self.info)
            self.zc.register_service(info, allow_name_change=True)
            self.info, self.announced = info, (me, self.E.anchor)
        except Exception as e:
            self.log(f'  mDNS: could not announce this device: {e}')

    def _resolve(self, name):
        info = self.zc.get_service_info(SERVICE, name, timeout=3000)
        if not info or not info.parsed_addresses():
            return
        props = {k.decode(): (v or b'').decode() for k, v in info.properties.items()}
        me = None
        try:
            me = __import__('peer.proto', fromlist=['peer_id']).peer_id(self.E.identity())
        except Exception:
            pass
        if props.get('peer') == me:
            return
        with self.lock:
            self.peers[name] = {'host': info.parsed_addresses()[0], 'port': info.port, 'root': props.get('root', ''),
                                'peer': props.get('peer')}
        self.wake.set()

    # ---------- automatic sync ----------
    def _on_change(self, why):
        if self.zc:   # e.g. the plant was just created: announce it (returns at once when nothing changed)
            threading.Thread(target=self._advertise, daemon=True).start()
        if why == 'local':
            self._due = time.time() + AFTER_CHANGE
            self.wake.set()

    def _auto(self):
        while True:
            self.wake.wait(timeout=max(0.5, min(self.cfg.get('sync_interval', 120), self._due - time.time())))
            self.wake.clear()
            if time.time() < self._due - 0.5 and not self._new_peer():
                continue
            self._due = time.time() + self.cfg.get('sync_interval', 120)
            self.sync_all()

    def _new_peer(self):
        with self.lock:
            return any(p['peer'] not in self.status for p in self.peers.values())

    def sync_all(self):
        with self.lock:
            peers = list(self.peers.values())
        root = (self.E.anchor or '')[:16]
        for p in peers:
            if root and p['root'] == root:
                try:
                    self.sync_one(p['host'], p['port'])
                except Exception:
                    pass   # recorded in status; the next device still gets its turn

    def sync_one(self, host, port, adopt_root=None):
        """-> (remote, stats); records the outcome; raises on failure."""
        try:
            remote, st = S.sync_with(self.E, host, port, adopt_root=adopt_root, timeout=20)
        except (S.SyncError, OSError, Exception) as e:
            self._record(None, f'{host}:{port}', False, str(e), 'out')
            raise
        self._record(remote, f'{host}:{port}', True, st, 'out')
        if adopt_root:
            self._advertise()
        return remote, st

    def _record(self, remote, address, ok, result, direction):
        key = remote or address
        with self.lock:
            prev = self.status.get(key, {})
            self.status[key] = {**prev, 'peer': remote, 'address': address if direction == 'out' else prev.get('address', address),
                                'at': int(time.time()), 'ok': ok, 'direction': direction,
                                **({'result': result, 'error': None} if ok else {'error': result})}
        if ok and (result['received'] or result['sent']):
            self.log(f'  sync {"with" if direction == "out" else "from"} {(remote or address)[:12]}…: '
                     f'received {result["received"]}, sent {result["sent"]}')

    def snapshot(self):
        """For the UI: what this node knows about the devices around it."""
        with self.lock:
            peers = list({p['peer']: dict(p) for p in self.peers.values()}.values())   # one per device
            status = {k: dict(v) for k, v in self.status.items()}
        return {'discovery': self.discovery, 'port': getattr(self, 'port', None), 'found': peers, 'syncs': status}

    def joined(self):
        """Call after this node joined a plant: announce the new root."""
        self._advertise()
        self.wake.set()


def _lan_ips():
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))   # no packet is sent: this only picks the outgoing interface
        ips.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    return sorted(ips) or ['127.0.0.1']
