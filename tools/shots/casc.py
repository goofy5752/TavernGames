"""A small read-only reader of a local WoW install's CASC storage, for client_art.py.

It follows .build.info to the build config, then the encoding and root manifests,
the local .idx indexes and the data.NNN archives, and unpacks BLTE (plain and zlib
chunks; encrypted ones are refused). A file is found by its path through the
Jenkins name hash the root manifest keeps, or by its FileDataID.
"""
import os, struct, zlib, glob

def hashlittle2(data, pc=0, pb=0):
    mask = 0xFFFFFFFF
    length = len(data)
    a = b = c = (0xdeadbeef + length + pc) & mask
    c = (c + pb) & mask
    def rot(x, k): return ((x << k) | (x >> (32 - k))) & mask
    i = 0
    while length > 12:
        a = (a + struct.unpack_from('<I', data, i)[0]) & mask
        b = (b + struct.unpack_from('<I', data, i + 4)[0]) & mask
        c = (c + struct.unpack_from('<I', data, i + 8)[0]) & mask
        a = (a - c) & mask; a ^= rot(c, 4);  c = (c + b) & mask
        b = (b - a) & mask; b ^= rot(a, 6);  a = (a + c) & mask
        c = (c - b) & mask; c ^= rot(b, 8);  b = (b + a) & mask
        a = (a - c) & mask; a ^= rot(c, 16); c = (c + b) & mask
        b = (b - a) & mask; b ^= rot(a, 19); a = (a + c) & mask
        c = (c - b) & mask; c ^= rot(b, 4);  b = (b + a) & mask
        length -= 12; i += 12
    if length == 0:
        return c, b
    tail = data[i:] + b'\0' * (12 - length)
    a = (a + struct.unpack_from('<I', tail, 0)[0]) & mask
    b = (b + struct.unpack_from('<I', tail, 4)[0]) & mask
    c = (c + struct.unpack_from('<I', tail, 8)[0]) & mask
    c ^= b; c = (c - rot(b, 14)) & mask
    a ^= c; a = (a - rot(c, 11)) & mask
    b ^= a; b = (b - rot(a, 25)) & mask
    c ^= b; c = (c - rot(b, 16)) & mask
    a ^= c; a = (a - rot(c, 4)) & mask
    b ^= a; b = (b - rot(a, 14)) & mask
    c ^= b; c = (c - rot(b, 24)) & mask
    return c, b

def name_hash(path):
    c, b = hashlittle2(path.upper().replace('/', '\\').encode('ascii'))
    return (c << 32) | b

def blte(buf):
    assert buf[:4] == b'BLTE', buf[:4]
    hsize = struct.unpack_from('>I', buf, 4)[0]
    out = []
    if hsize == 0:
        chunks = [(len(buf) - 8, None)]
        pos = 8
    else:
        count = struct.unpack_from('>I', buf, 8)[0] & 0xFFFFFF
        chunks = []
        for k in range(count):
            csize, dsize = struct.unpack_from('>II', buf, 12 + k * 24)
            chunks.append((csize, dsize))
        pos = hsize
    for csize, _ in chunks:
        chunk = buf[pos:pos + csize]; pos += csize
        mode = chunk[:1]
        if mode == b'N': out.append(chunk[1:])
        elif mode == b'Z': out.append(zlib.decompress(chunk[1:]))
        elif mode == b'E': raise ValueError('encrypted chunk')
        else: raise ValueError('BLTE mode %r' % mode)
    return b''.join(out)

class Casc:
    def __init__(self, wow_dir, product):
        self.data = os.path.join(wow_dir, 'Data')
        rows = open(os.path.join(wow_dir, '.build.info'), encoding='utf-8').read().splitlines()
        head = [h.split('!')[0] for h in rows[0].split('|')]
        info = None
        for line in rows[1:]:
            r = dict(zip(head, line.split('|')))
            if r.get('Product') == product: info = r
        key = info['Build Key']
        cfg = {}
        for line in open(os.path.join(self.data, 'config', key[:2], key[2:4], key), encoding='utf-8'):
            if ' = ' in line:
                k, v = line.strip().split(' = ', 1); cfg[k] = v.split()
        self.cfg = cfg
        self._load_index()
        enc_ekey = bytes.fromhex(cfg['encoding'][1])
        self._load_encoding(self.read_ekey(enc_ekey))
        self._load_root(self.read_ckey(bytes.fromhex(cfg['root'][0])))

    def _load_index(self):
        best = {}
        for p in glob.glob(os.path.join(self.data, 'data', '*.idx')):
            n = os.path.basename(p)
            bucket, ver = int(n[:2], 16), int(n[2:10], 16)
            if bucket not in best or ver > best[bucket][0]: best[bucket] = (ver, p)
        self.index = {}
        for _, p in best.values():
            d = open(p, 'rb').read()
            hhs = struct.unpack_from('<I', d, 0)[0]
            pos = (8 + hhs + 0x0F) & ~0x0F
            esize = struct.unpack_from('<I', d, pos)[0]; pos += 8
            for off in range(pos, pos + esize, 18):
                ek = d[off:off + 9]
                hi = d[off + 9]; lo = struct.unpack_from('>I', d, off + 10)[0]
                v = (hi << 32) | lo
                archive, offset = v >> 30, v & 0x3FFFFFFF
                size = struct.unpack_from('<I', d, off + 14)[0]
                self.index.setdefault(ek, (archive, offset, size))

    def read_ekey(self, ekey):
        archive, offset, size = self.index[ekey[:9]]
        with open(os.path.join(self.data, 'data', 'data.%03d' % archive), 'rb') as f:
            f.seek(offset + 30)
            return blte(f.read(size - 30))

    def _load_encoding(self, d):
        assert d[:2] == b'EN'
        ck, ek = d[3], d[4]
        cpage = struct.unpack_from('>H', d, 5)[0] * 1024
        ccount = struct.unpack_from('>I', d, 9)[0]
        espec = struct.unpack_from('>I', d, 18)[0]
        pos = 22 + espec + ccount * 32
        self.enc = {}
        for p in range(ccount):
            page = d[pos + p * cpage: pos + (p + 1) * cpage]
            i = 0
            while i + 6 + ck <= len(page):
                n = page[i]
                if n == 0: break
                ckey = page[i + 6:i + 6 + ck]
                self.enc[ckey] = page[i + 6 + ck:i + 6 + ck + ek]
                i += 6 + ck + n * ek

    def read_ckey(self, ckey):
        return self.read_ekey(self.enc[ckey])

    def _load_root(self, d):
        self.by_hash, self.by_fdid = {}, {}
        assert d[:4] == b'TSFM', d[:4]
        hsize, version = struct.unpack_from('<II', d, 4)
        if version == 2 or hsize == 0x18:
            pos = hsize
        else:
            pos = 12  # v1: magic, total, named
            version = 1
        while pos < len(d):
            if version == 2:
                n, locale, f1, f2, f3 = struct.unpack_from('<IIIIB', d, pos); pos += 17
                flags = f1 | f2 | (f3 << 17)
            else:
                n, flags, locale = struct.unpack_from('<III', d, pos); pos += 12
            fdid, ids = -1, []
            for k in range(n):
                fdid += struct.unpack_from('<i', d, pos + k * 4)[0] + 1; ids.append(fdid)
            pos += n * 4
            ckeys = [d[pos + k * 16:pos + k * 16 + 16] for k in range(n)]; pos += n * 16
            hashes = None
            if not (flags & 0x10000000):
                hashes = struct.unpack_from('<%dQ' % n, d, pos); pos += n * 8
            enus = (locale & 0x2) or locale == 0xFFFFFFFF or locale == 0
            for k in range(n):
                if ids[k] not in self.by_fdid or enus: self.by_fdid[ids[k]] = ckeys[k]
                if hashes and (hashes[k] not in self.by_hash or enus): self.by_hash[hashes[k]] = ids[k]

    def fdid(self, path):
        return self.by_hash.get(name_hash(path))

    def read_path(self, path):
        f = self.fdid(path)
        if f is None: return None
        return self.read_ckey(self.by_fdid[f])
