// cargo: bench/std/unicode-rs (unicode-width 0.2.2, offline)
// bench/std width, Rust half: unicode-width's char widths summed (None:
// 0); with the argument `str`, UnicodeWidthStr::width.
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};
include!("text_gen.rs");

fn main() {
    if std::env::args().nth(1).as_deref() == Some("str") {
        run("width (str)", &[0, 2], |s| s.width() as u64);
    } else {
        run("width", &[0, 2], |s| s.chars().map(|c| c.width().unwrap_or(0) as u64).sum());
    }
}
