// bench/std chars, Rust half: s.chars().count() plus the sum of the chars.
include!("text_gen.rs");

fn main() {
    run("chars", &[0, 4], |s| {
        let n = s.chars().count() as u64;
        n.wrapping_add(s.chars().map(|c| c as u64).sum::<u64>())
    });
}
