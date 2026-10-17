// bench/std spawn (0.20): 1000 times, Command::new("/usr/bin/true").status(),
// then the number that exited 0 (as spawn.tach). std only.
use std::process::Command;

fn main() {
    let mut ok = 0;
    for _ in 0..1000 {
        if Command::new("/usr/bin/true").status().unwrap().success() {
            ok += 1;
        }
    }
    println!("{}", ok);
}
