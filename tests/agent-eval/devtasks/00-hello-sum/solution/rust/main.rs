// Reads integers from stdin, one per line (blank lines ignored), and
// prints their sum.

use std::io::Read;

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let mut total: i64 = 0;
    for line in data.lines() {
        let t = line.trim();
        if t.is_empty() {
            continue;
        }
        total += t.parse::<i64>().unwrap();
    }
    println!("{}", total);
}
