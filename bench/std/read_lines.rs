// bench/std: read a 256 MB file of text lines (made by read_lines.vl
// --make) with a BufReader: `lines()` (a String per line), or with the
// argument `reuse` before the path, `read_line` into one String. Prints
// the lines, their bytes (each '\n' included) and the sum of each line's
// first byte.
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let reuse = args.len() == 3 && args[1] == "reuse";
    let path = &args[args.len() - 1];
    let mut r = BufReader::new(File::open(path).unwrap());
    let (mut lines, mut bytes, mut first) = (0i64, 0i64, 0i64);
    if reuse {
        let mut line = String::new();
        loop {
            line.clear();
            let n = r.read_line(&mut line).unwrap();
            if n == 0 {
                break;
            }
            lines += 1;
            bytes += n as i64;
            first += line.as_bytes()[0] as i64;
        }
    } else {
        for line in r.lines() {
            let line = line.unwrap();
            lines += 1;
            bytes += line.len() as i64 + 1;
            first += if line.is_empty() { b'\n' as i64 } else { line.as_bytes()[0] as i64 };
        }
    }
    println!("{} {} {}", lines, bytes, first);
}
