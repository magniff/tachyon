// cargo: bench/std/unicode-rs (unicode-segmentation 1.13.3, unicode-width 0.2.2, offline)
// bench/std term_feed, Rust half: the 0.23 terminal's inner loop as a Rust
// terminal would write it with the crates. A run of printable ASCII adds
// its length to cells and clusters; a C0 control or DEL adds 1 to
// controls; a run of non-ASCII text (up to the next ASCII byte) is
// segmented with graphemes(true), each cluster adding 1 to clusters and
// UnicodeWidthStr::width to cells. (The crates have no incremental
// segmenter, so an ASCII letter that combining marks follow is not joined
// to them, and the str width has unicode-width's own rules: the checksum
// differs from vole's.)
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::UnicodeWidthStr;
include!("text_gen.rs");

fn feed(s: &str) -> u64 {
    let b = s.as_bytes();
    let n = b.len();
    let (mut cells, mut clusters, mut controls) = (0u64, 0u64, 0u64);
    let mut i = 0;
    while i < n {
        let c = b[i];
        if (0x20..0x7f).contains(&c) {
            let mut j = i + 1;
            while j < n && (0x20..0x7f).contains(&b[j]) {
                j += 1;
            }
            cells += (j - i) as u64;
            clusters += (j - i) as u64;
            i = j;
        } else if c < 0x80 {
            controls += 1;
            i += 1;
        } else {
            let mut j = i + 1;
            while j < n && b[j] >= 0x80 {
                j += 1;
            }
            for g in s[i..j].graphemes(true) {
                clusters += 1;
                cells += g.width() as u64;
            }
            i = j;
        }
    }
    cells + (clusters << 20) + (controls << 40)
}

fn main() {
    run("term_feed", &[0, 2, 3], feed);
}
