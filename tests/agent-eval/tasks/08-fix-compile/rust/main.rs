// Formats comma-separated lines from stdin as a boxed text table.

mod render;
mod table;

use std::io::Read;

fn main() {
    let mut input = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    let t = parse_table(&input);
    let mut out = String::new();
    if t.ncols > 0 {
        render::render(&t, &mut out);
    }
    print!("{}", out);
}
