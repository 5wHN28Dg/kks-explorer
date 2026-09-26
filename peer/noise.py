"""Noise_XX_25519_ChaChaPoly_SHA256 (the Noise Protocol Framework, revision 34, https://noiseprotocol.org/noise.html),
just the one pattern KKS Explorer uses to connect two peers (docs/PROTOCOL.md §15). Checked against the published
test vector (peer/vectors/noise-xx.json, from cacophony) in tests/test_sync.py.

    -> e
    <- e, ee, s, es
    -> s, se
"""
import hashlib, hmac, struct

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

NAME = b'Noise_XX_25519_ChaChaPoly_SHA256'
HASHLEN, DHLEN, MAX_MSG = 32, 32, 65535


class NoiseError(Exception):
    pass


def _pub(priv):
    return priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def x25519(priv_bytes):
    return X25519PrivateKey.from_private_bytes(priv_bytes)


def _dh(priv, pub_bytes):
    return priv.exchange(X25519PublicKey.from_public_bytes(pub_bytes))


def _hkdf(ck, ikm):
    t = hmac.new(ck, ikm, hashlib.sha256).digest()
    o1 = hmac.new(t, b'\x01', hashlib.sha256).digest()
    o2 = hmac.new(t, o1 + b'\x02', hashlib.sha256).digest()
    return o1, o2


class CipherState:
    def __init__(self, k=None):
        self.k, self.n = k, 0

    def _nonce(self):
        if self.n >= 2 ** 64 - 1:
            raise NoiseError('nonce exhausted')
        return b'\x00' * 4 + struct.pack('<Q', self.n)

    def encrypt(self, ad, pt):
        if self.k is None:
            return pt
        ct = ChaCha20Poly1305(self.k).encrypt(self._nonce(), pt, ad)
        self.n += 1
        return ct

    def decrypt(self, ad, ct):
        if self.k is None:
            return ct
        try:
            pt = ChaCha20Poly1305(self.k).decrypt(self._nonce(), ct, ad)
        except Exception:
            raise NoiseError('decryption failed')
        self.n += 1
        return pt


class Handshake:
    """One side of an XX handshake. write()/read() the three messages in turn; then split() -> (send, recv)."""
    def __init__(self, initiator, static_priv, prologue=b'', ephemeral_priv=None):
        self.initiator, self.s = initiator, static_priv
        self.e = ephemeral_priv          # fixed only for test vectors
        self.re = self.rs = None
        h = NAME + b'\x00' * (HASHLEN - len(NAME)) if len(NAME) <= HASHLEN else hashlib.sha256(NAME).digest()
        self.h, self.ck, self.c = h, h, CipherState()
        self._mix_hash(prologue)
        self.step = 0

    def _mix_hash(self, data):
        self.h = hashlib.sha256(self.h + data).digest()

    def _mix_key(self, ikm):
        self.ck, k = _hkdf(self.ck, ikm)
        self.c = CipherState(k)

    def _enc_hash(self, pt):
        ct = self.c.encrypt(self.h, pt)
        self._mix_hash(ct)
        return ct

    def _dec_hash(self, ct):
        pt = self.c.decrypt(self.h, ct)
        self._mix_hash(ct)
        return pt

    def _my_turn(self):
        return (self.step % 2 == 0) == self.initiator

    def write(self, payload=b''):
        if not self._my_turn() or self.step > 2:
            raise NoiseError('not our turn')
        out = b''
        if self.step == 0:                       # -> e
            self.e = self.e or X25519PrivateKey.generate()
            out += _pub(self.e); self._mix_hash(_pub(self.e))
        elif self.step == 1:                     # <- e, ee, s, es
            self.e = self.e or X25519PrivateKey.generate()
            out += _pub(self.e); self._mix_hash(_pub(self.e))
            self._mix_key(_dh(self.e, self.re))
            out += self._enc_hash(_pub(self.s))
            self._mix_key(_dh(self.s, self.re))
        else:                                    # -> s, se
            out += self._enc_hash(_pub(self.s))
            self._mix_key(_dh(self.s, self.re))
        out += self._enc_hash(payload)
        self.step += 1
        if len(out) > MAX_MSG:
            raise NoiseError('handshake message too long')
        return out

    def read(self, msg):
        if self._my_turn() or self.step > 2:
            raise NoiseError('not their turn')
        try:
            if self.step == 0:
                self.re, rest = msg[:DHLEN], msg[DHLEN:]
                self._mix_hash(self.re)
            elif self.step == 1:
                self.re, rest = msg[:DHLEN], msg[DHLEN:]
                self._mix_hash(self.re)
                self._mix_key(_dh(self.e, self.re))
                self.rs, rest = self._dec_hash(rest[:DHLEN + 16]), rest[DHLEN + 16:]
                self._mix_key(_dh(self.e, self.rs))
            else:
                self.rs, rest = self._dec_hash(msg[:DHLEN + 16]), msg[DHLEN + 16:]
                self._mix_key(_dh(self.e, self.rs))
            if len(self.re) != DHLEN or (self.rs is not None and len(self.rs) != DHLEN):
                raise NoiseError('short message')
            payload = self._dec_hash(rest)
        except (ValueError, TypeError) as e:
            raise NoiseError(f'bad handshake message: {e}')
        self.step += 1
        return payload

    def done(self):
        return self.step == 3

    def split(self):
        """-> (cipher for sending, cipher for receiving)"""
        k1, k2 = _hkdf(self.ck, b'')
        c1, c2 = CipherState(k1), CipherState(k2)
        return (c1, c2) if self.initiator else (c2, c1)
