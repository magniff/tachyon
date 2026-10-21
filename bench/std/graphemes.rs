// cargo: bench/std/unicode-rs (unicode-segmentation 1.13.3, offline)
// bench/std graphemes, Rust half: graphemes(true): the count of clusters
// plus the sum of their byte lengths squared.
use unicode_segmentation::UnicodeSegmentation;
include!("text_gen.rs");

fn main() {
    run("graphemes", &[0, 4, 3], |s| {
        let mut r = 0u64;
        for g in s.graphemes(true) {
            let n = g.len() as u64;
            r = r.wrapping_add(1 + n * n);
        }
        r
    });
}
