// Reads integers from stdin, one per line, and prints the largest.

use std::io::Read;

// All of stdin.
fn read_all() -> String {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    data
}

// The integers in `s`, one per line; blank lines are skipped.
fn parse_numbers(s: &str) -> Vec<i64> {
    let mut out = Vec::new();
    for line in s.lines() {
        let t = line.trim();
        if !t.is_empty() {
            out.push(t.parse::<i64>().unwrap());
        }
    }
    out
}

// The largest value of a non-empty slice.
fn largest(values: &[i64]) -> i64 {
    let mut best = 0;
    for &x in values {
        if x > best {
            best = x;
        }
    }
    best
}

fn main() {
    let data = read_all();
    let numbers = parse_numbers(&data);
    println!("{}", largest(&numbers));
}
