// bench/std's text benchmarks' input, Rust half (include!d by the text
// benchmarks): text_gen.tach's five kinds of text, byte for byte, and the
// same benchmark loop (`KIND SUM` on stdout, `NAME KIND: MB/s` on stderr).

const SIZE: usize = 16 * 1024 * 1024;

fn kind_name(k: usize) -> &'static str {
    ["source", "latin", "cjk", "emoji", "mixed"][k]
}

fn next(s: &mut u64) -> u64 {
    let mut x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    x
}

fn put(b: &mut Vec<u8>, cp: u32) {
    let mut e = [0u8; 4];
    b.extend_from_slice(char::from_u32(cp).unwrap().encode_utf8(&mut e).as_bytes());
}

fn word(b: &mut Vec<u8>, x: u64) {
    let n = 1 + (x >> 8) % 9;
    for i in 0..n {
        b.push((97 + (x >> (12 + i * 5)) % 26) as u8);
    }
}

const ACCENTED: [u32; 16] = [0xe9, 0xe8, 0xea, 0xe0, 0xe7, 0xf4, 0xfb, 0xe4, 0xf6, 0xfc, 0xdf, 0xc9,
    0xef, 0xee, 0xf9, 0x153];

fn latin_word(b: &mut Vec<u8>, x: u64) {
    let n = 2 + (x >> 8) % 9;
    for i in 0..n {
        let y = x >> (12 + i * 5);
        if y % 6 == 0 {
            put(b, ACCENTED[((y >> 1) % 16) as usize]);
        } else {
            b.push((97 + y % 26) as u8);
        }
    }
}

const CJK_PUNCT: [u32; 6] = [0x3001, 0x3002, 0xff0c, 0xff01, 0x300c, 0x300d];

fn cjk_run(b: &mut Vec<u8>, s: &mut u64, x: u64) {
    let n = 4 + (x >> 8) % 20;
    for _ in 0..n {
        put(b, (0x4e00 + next(s) % 0x5200) as u32);
    }
    put(b, CJK_PUNCT[((x >> 16) % 6) as usize]);
}

const EMOJI: [u32; 26] = [
    0x1f600, 0, 0x1f680, 0, 0x2764, 0xfe0f, 0, 0x1f44d, 0x1f3fd, 0, 0x1f468, 0x200d, 0x1f469,
    0x200d, 0x1f467, 0, 0x1f1eb, 0x1f1f7, 0, 0x33, 0xfe0f, 0x20e3, 0, 0x1f9d1, 0x200d, 0x1f4bb,
];
const EMOJI_STARTS: [usize; 7] = [0, 2, 4, 7, 10, 16, 19];

fn emoji(b: &mut Vec<u8>, x: u64) {
    let k = ((x >> 8) % 8) as usize;
    if k == 7 {
        put(b, (0x1f600 + (x >> 16) % 0x50) as u32);
        return;
    }
    let mut i = if k == 6 { 23 } else { EMOJI_STARTS[k] };
    while i < 26 && EMOJI[i] != 0 {
        put(b, EMOJI[i]);
        i += 1;
    }
}

fn make(k: usize) -> Vec<u8> {
    let mut b: Vec<u8> = Vec::with_capacity(SIZE + 1024);
    let mut s: u64 = 0x9e3779b97f4a7c15 ^ ((k as u64 + 1).wrapping_mul(0x2545f4914f6cdd1d));
    let mut col: usize = 0;
    while b.len() < SIZE {
        let x = next(&mut s);
        let start = b.len();
        if k == 0 {
            let t = x % 10;
            if t < 6 {
                word(&mut b, x);
            } else if t == 6 {
                b.extend_from_slice(b"(x, 1);");
            } else if t == 7 {
                b.extend_from_slice(b"{ }");
            } else if t == 8 {
                b.extend_from_slice(b"= 0");
            } else {
                b.extend_from_slice(b"\n    ");
                col = 0;
            }
        } else if k == 1 {
            latin_word(&mut b, x);
        } else if k == 2 {
            cjk_run(&mut b, &mut s, x);
        } else if k == 3 {
            if x % 4 == 0 { emoji(&mut b, x); } else { word(&mut b, x); }
        } else {
            let t = x % 100;
            if t < 50 {
                word(&mut b, x);
            } else if t < 62 {
                latin_word(&mut b, x);
            } else if t < 68 {
                for i in 0..3 + (x >> 8) % 6 { put(&mut b, (0x430 + (x >> (12 + i * 5)) % 32) as u32); }
            } else if t < 72 {
                for i in 0..3 + (x >> 8) % 6 { put(&mut b, (0x3b1 + (x >> (12 + i * 5)) % 25) as u32); }
            } else if t < 80 {
                cjk_run(&mut b, &mut s, x);
            } else if t < 85 {
                put(&mut b, (0xac00 + (x >> 8) % 11172) as u32);
                put(&mut b, (0x1100 + (x >> 24) % 19) as u32);
                put(&mut b, (0x1161 + (x >> 32) % 21) as u32);
                put(&mut b, (0x11a8 + (x >> 40) % 27) as u32);
            } else if t < 90 {
                put(&mut b, (0x915 + (x >> 8) % 32) as u32);
                put(&mut b, 0x94d);
                put(&mut b, (0x915 + (x >> 16) % 32) as u32);
                put(&mut b, (0x93e + (x >> 24) % 10) as u32);
            } else if t < 95 {
                b.push(b'e');
                put(&mut b, (0x300 + (x >> 8) % 0x30) as u32);
            } else {
                emoji(&mut b, x);
            }
        }
        col += b.len() - start;
        if k != 0 {
            if col > 60 + ((x >> 56) % 20) as usize {
                b.push(b'\n');
                col = 0;
            } else if k != 2 {
                b.push(b' ');
            }
        } else if col > 0 {
            b.push(b' ');
        }
    }
    b.extend_from_slice(b"\n\n\n\n");
    b
}

fn run(name: &str, kinds: &[usize], op: impl Fn(&str) -> u64) {
    for &k in kinds {
        let data = make(k);
        let text = std::str::from_utf8(&data).unwrap();
        let mut sum = 0u64;
        let mut best = f64::MAX;
        for r in 0..10 {
            let s = std::hint::black_box(&text[..text.len() - r % 4]);
            let t = std::time::Instant::now();
            let x = op(s);
            let dt = t.elapsed().as_secs_f64();
            sum = sum.wrapping_add(std::hint::black_box(x));
            best = best.min(dt);
        }
        println!("{} {}", kind_name(k), sum);
        eprintln!("{} {}: {:.0} MB/s", name, kind_name(k), text.len() as f64 / best / 1e6);
    }
}
