## SHA-256 for the test harness only (FIPS 180-4), to match the Python trace's hashes.
const K: array[64, uint32] = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
  0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32, 0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
  0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32, 0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
  0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32, 0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
  0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
  0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32, 0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]
proc rotr(x: uint32, n: int): uint32 = (x shr n) or (x shl (32 - n))
proc sha256hex*(msg: string): string =
  var h = [0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32, 0x510e527f'u32, 0x9b05688c'u32,
           0x1f83d9ab'u32, 0x5be0cd19'u32]
  var m = msg
  let bitLen = uint64(msg.len) * 8
  m.add '\x80'
  while m.len mod 64 != 56: m.add '\0'
  for i in countdown(7, 0): m.add char((bitLen shr (8 * i)) and 0xff)
  var w: array[64, uint32]
  for blk in 0 ..< m.len div 64:
    for t in 0 .. 15:
      let p = blk * 64 + t * 4
      w[t] = (uint32(m[p].uint8) shl 24) or (uint32(m[p+1].uint8) shl 16) or (uint32(m[p+2].uint8) shl 8) or uint32(m[p+3].uint8)
    for t in 16 .. 63:
      let s0 = rotr(w[t-15], 7) xor rotr(w[t-15], 18) xor (w[t-15] shr 3)
      let s1 = rotr(w[t-2], 17) xor rotr(w[t-2], 19) xor (w[t-2] shr 10)
      w[t] = w[t-16] + s0 + w[t-7] + s1
    var a = h
    for t in 0 .. 63:
      let S1 = rotr(a[4], 6) xor rotr(a[4], 11) xor rotr(a[4], 25)
      let ch = (a[4] and a[5]) xor ((not a[4]) and a[6])
      let t1 = a[7] + S1 + ch + K[t] + w[t]
      let S0 = rotr(a[0], 2) xor rotr(a[0], 13) xor rotr(a[0], 22)
      let mj = (a[0] and a[1]) xor (a[0] and a[2]) xor (a[1] and a[2])
      let t2 = S0 + mj
      let old = a          # a copy: Nim builds an array literal in place
      a = [t1 + t2, old[0], old[1], old[2], old[3] + t1, old[4], old[5], old[6]]
    for i in 0 .. 7: h[i] += a[i]
  const hx = "0123456789abcdef"
  for v in h:
    for i in countdown(7, 0): result.add hx[int((v shr (4 * i)) and 0xf)]
