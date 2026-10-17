// bench/std utf8_validate, Rust half: std::str::from_utf8 over each kind of
// text (text_gen.rs); the result is the valid length.
include!("text_gen.rs");

fn main() {
    run("utf8_validate", &[0, 1, 2, 3], |s| match std::str::from_utf8(std::hint::black_box(s.as_bytes())) {
        Ok(v) => v.len() as u64,
        Err(e) => e.valid_up_to() as u64,
    });
}
