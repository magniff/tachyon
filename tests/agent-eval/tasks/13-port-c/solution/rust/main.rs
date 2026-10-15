// lzss: a small LZSS compressor and decompressor, ported from reference.c.
//
// The first line of stdin is the mode, `compress` or `decompress`; the
// rest is the input. See the task for the stream format.

use std::io::{self, Read, Write};

const WINDOW_SIZE: usize = 4096; // distances 1..4096
const WINDOW_MASK: usize = WINDOW_SIZE - 1;
const MIN_MATCH: usize = 3;
const MAX_MATCH: usize = 18;
const HASH_BITS: u32 = 13;
const HASH_SIZE: usize = 1 << HASH_BITS;
const MAX_CHAIN: usize = 64; // candidates looked at per position
const HEADER_SIZE: usize = 11;

// ---- CRC-32 (the zlib one: reflected, polynomial 0xEDB88320) ----

fn crc_table() -> Vec<u32> {
    let mut t = vec![0u32; 256];
    for n in 0..256u32 {
        let mut c = n;
        for _ in 0..8 {
            c = if c & 1 != 0 { 0xEDB88320 ^ (c >> 1) } else { c >> 1 };
        }
        t[n as usize] = c;
    }
    t
}

fn crc32(table: &[u32], p: &[u8]) -> u32 {
    let mut c: u32 = 0xFFFFFFFF;
    for &b in p {
        c = table[((c ^ b as u32) & 0xFF) as usize] ^ (c >> 8);
    }
    c ^ 0xFFFFFFFF
}

fn push_hex32(out: &mut Vec<u8>, v: u32) {
    for i in (0..8).rev() {
        out.push(DIGITS[((v >> (4 * i)) & 15) as usize]);
    }
}

fn push_num(out: &mut Vec<u8>, v: usize) {
    out.extend_from_slice(v.to_string().as_bytes());
}

const DIGITS: &[u8] = b"0123456789abcdef";

fn get_u32le(p: &[u8]) -> u32 {
    p[0] as u32 | (p[1] as u32) << 8 | (p[2] as u32) << 16 | (p[3] as u32) << 24
}

fn put_u32le(out: &mut Vec<u8>, v: u32) {
    for i in 0..4 {
        out.push((v >> (8 * i)) as u8);
    }
}

// ---- the match finder: hash chains over the last WINDOW_SIZE positions ----

struct Finder {
    head: Vec<i64>, // newest position with this hash, or -1
    prev: Vec<i64>, // prev[p & WINDOW_MASK]: the position before p in p's chain
}

// The hash of the 3 bytes at p: a multiplicative hash, 32-bit wrapping.
fn hash3(p: &[u8]) -> usize {
    let v: u32 = (p[0] as u32) << 16 | (p[1] as u32) << 8 | p[2] as u32;
    (v.wrapping_mul(2654435761) >> (32 - HASH_BITS)) as usize
}

impl Finder {
    fn insert(&mut self, data: &[u8], pos: usize) {
        if pos + MIN_MATCH > data.len() {
            return;
        }
        let h = hash3(&data[pos..]);
        self.prev[pos & WINDOW_MASK] = self.head[h];
        self.head[h] = pos as i64;
    }

    // (length, distance) of the longest match at pos; (0, 0) if none.
    fn find_match(&self, data: &[u8], pos: usize) -> (usize, usize) {
        let n = data.len();
        if pos + MIN_MATCH > n {
            return (0, 0);
        }
        let max = if n - pos < MAX_MATCH { n - pos } else { MAX_MATCH };
        let mut best = 0;
        let mut dist = 0;
        let mut cand = self.head[hash3(&data[pos..])];
        let mut chain = 0;
        while cand >= 0 && chain < MAX_CHAIN {
            let c = cand as usize;
            let d = pos - c;
            if d > WINDOW_SIZE {
                break;
            }
            let mut len = 0;
            while len < max && data[c + len] == data[pos + len] {
                len += 1;
            }
            if len > best {
                best = len;
                dist = d;
                if len == max {
                    break;
                }
            }
            cand = self.prev[c & WINDOW_MASK];
            chain += 1;
        }
        if best < MIN_MATCH {
            return (0, 0);
        }
        (best, dist)
    }
}

// ---- compress ----

struct Writer {
    out: Vec<u8>,
    flag_at: usize,
    nbits: u32,
    literals: usize,
    matches: usize,
}

impl Writer {
    fn start_token(&mut self, is_match: bool) {
        if self.nbits == 8 || self.out.len() == HEADER_SIZE {
            self.flag_at = self.out.len();
            self.out.push(0);
            self.nbits = 0;
        }
        if is_match {
            self.out[self.flag_at] |= 1u8 << self.nbits;
        }
        self.nbits += 1;
    }

    fn emit_literal(&mut self, c: u8) {
        self.start_token(false);
        self.out.push(c);
        self.literals += 1;
    }

    fn emit_match(&mut self, dist: usize, len: usize) {
        let d = dist - 1;
        self.start_token(true);
        self.out.push((d & 0xFF) as u8);
        self.out.push((((d >> 8) << 4) | (len - MIN_MATCH)) as u8);
        self.matches += 1;
    }
}

fn compress(table: &[u32], data: &[u8], res: &mut Vec<u8>) {
    let n = data.len();
    let mut f = Finder { head: vec![-1; HASH_SIZE], prev: vec![0; WINDOW_SIZE] };
    let mut w = Writer { out: Vec::new(), flag_at: 0, nbits: 0, literals: 0, matches: 0 };
    let crc = crc32(table, data);
    w.out.push(b'L');
    w.out.push(b'Z');
    w.out.push(1);
    put_u32le(&mut w.out, n as u32);
    put_u32le(&mut w.out, crc);

    let mut inserted = 0;
    let mut pos = 0;
    while pos < n {
        while inserted < pos {
            f.insert(data, inserted);
            inserted += 1;
        }
        let (len, dist) = f.find_match(data, pos);
        if len > 0 && pos + 1 < n {
            while inserted < pos + 1 {
                f.insert(data, inserted);
                inserted += 1;
            }
            let (len2, _) = f.find_match(data, pos + 1);
            if len2 > len {
                w.emit_literal(data[pos]);
                pos += 1;
                continue;
            }
        }
        if len > 0 {
            w.emit_match(dist, len);
            pos += len;
        } else {
            w.emit_literal(data[pos]);
            pos += 1;
        }
    }

    res.extend_from_slice(b"compressed ");
    push_num(res, n);
    res.extend_from_slice(b" -> ");
    push_num(res, w.out.len());
    res.extend_from_slice(b" bytes (");
    push_num(res, w.literals);
    res.extend_from_slice(b" literals, ");
    push_num(res, w.matches);
    res.extend_from_slice(b" matches), crc32 ");
    push_hex32(res, crc);
    res.push(b'\n');
    for i in 0..w.out.len() {
        let c = w.out[i];
        res.push(DIGITS[(c >> 4) as usize]);
        res.push(DIGITS[(c & 15) as usize]);
        if i % 32 == 31 || i + 1 == w.out.len() {
            res.push(b'\n');
        }
    }
}

// ---- decompress ----

fn hex_value(c: u8) -> i32 {
    match c {
        b'0'..=b'9' => (c - b'0') as i32,
        b'a'..=b'f' => (c - b'a') as i32 + 10,
        b'A'..=b'F' => (c - b'A') as i32 + 10,
        _ => -1,
    }
}

// Hex text to bytes; whitespace is skipped. Err holds the error line.
fn unhex(text: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut high = -1;
    for i in 0..text.len() {
        let c = text[i];
        if c == b' ' || c == b'\t' || c == b'\r' || c == b'\n' {
            continue;
        }
        let v = hex_value(c);
        if v < 0 {
            return Err(format!("error: bad hex character at offset {}\n", i));
        }
        if high < 0 {
            high = v;
        } else {
            out.push((high << 4 | v) as u8);
            high = -1;
        }
    }
    if high >= 0 {
        return Err("error: odd number of hex digits\n".to_string());
    }
    Ok(out)
}

fn decode(table: &[u32], s: &[u8], res: &mut Vec<u8>) -> Result<(), String> {
    let n = s.len();
    if n < HEADER_SIZE {
        return Err("error: truncated header\n".to_string());
    }
    if s[0] != b'L' || s[1] != b'Z' || s[2] != 1 {
        return Err("error: bad magic\n".to_string());
    }
    let size = get_u32le(&s[3..]) as usize;
    let stored_crc = get_u32le(&s[7..]);
    let mut out: Vec<u8> = Vec::new();
    let mut p = HEADER_SIZE;
    let mut flags: u32 = 0;
    let mut nbits = 0;
    while out.len() < size {
        if nbits == 0 {
            if p >= n {
                return Err(format!("error: truncated stream at byte {}\n", p));
            }
            flags = s[p] as u32;
            p += 1;
            nbits = 8;
        }
        let is_match = flags & 1 != 0;
        flags >>= 1;
        nbits -= 1;
        if !is_match {
            if p >= n {
                return Err(format!("error: truncated stream at byte {}\n", p));
            }
            out.push(s[p]);
            p += 1;
            continue;
        }
        if p + 2 > n {
            return Err(format!("error: truncated stream at byte {}\n", p));
        }
        let dist = (s[p] as usize | ((s[p + 1] >> 4) as usize) << 8) + 1;
        let len = (s[p + 1] & 15) as usize + MIN_MATCH;
        if dist > out.len() {
            return Err(format!("error: bad distance {} at byte {}\n", dist, p));
        }
        if out.len() + len > size {
            return Err(format!("error: match overruns the data at byte {}\n", p));
        }
        p += 2;
        for _ in 0..len {
            let b = out[out.len() - dist];
            out.push(b);
        }
    }
    if p < n {
        return Err(format!("error: {} trailing bytes\n", n - p));
    }
    let crc = crc32(table, &out);
    if crc != stored_crc {
        let mut e = b"error: crc mismatch: stored ".to_vec();
        push_hex32(&mut e, stored_crc);
        e.extend_from_slice(b", computed ");
        push_hex32(&mut e, crc);
        e.push(b'\n');
        return Err(String::from_utf8(e).unwrap());
    }
    res.extend_from_slice(b"decompressed ");
    push_num(res, n);
    res.extend_from_slice(b" -> ");
    push_num(res, out.len());
    res.extend_from_slice(b" bytes, crc32 ");
    push_hex32(res, crc);
    res.push(b'\n');
    res.extend_from_slice(&out);
    Ok(())
}

fn decompress(table: &[u32], text: &[u8], res: &mut Vec<u8>) {
    let r = match unhex(text) {
        Ok(s) => decode(table, &s, res),
        Err(e) => Err(e),
    };
    if let Err(e) = r {
        res.extend_from_slice(e.as_bytes());
    }
}

// ---- main ----

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();
    let mut nl = 0;
    while nl < input.len() && input[nl] != b'\n' {
        nl += 1;
    }
    let mut mode_len = nl;
    if mode_len > 0 && input[mode_len - 1] == b'\r' {
        mode_len -= 1;
    }
    let rest = if nl < input.len() { nl + 1 } else { input.len() };
    let body = &input[rest..];
    let mode = &input[..mode_len];

    let table = crc_table();
    let mut res = Vec::new();
    if mode == b"compress" {
        compress(&table, body, &mut res);
    } else if mode == b"decompress" {
        decompress(&table, body, &mut res);
    } else {
        res.extend_from_slice(b"error: unknown mode\n");
    }
    io::stdout().write_all(&res).unwrap();
}
