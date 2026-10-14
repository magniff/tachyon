// Draws a table with borders: numeric columns right-aligned, the others
// left-aligned, every column as wide as its widest cell.

use crate::table::Table;

// An optional '-', digits, and optionally '.' and more digits.
fn is_number(s: &str) -> bool {
    let b = s.as_bytes();
    let mut i = 0;
    if i < b.len() && b[i] == b'-' {
        i += 1;
    }
    let digits_start = i;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    if i == digits_start {
        return false;
    }
    if i < b.len() && b[i] == b'.' {
        i += 1;
        let frac_start = i;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
        }
        if i == frac_start {
            return false;
        }
    }
    i == b.len()
}

// The width of each column: its longest cell, header included, at least 1.
pub fn column_widths(t: &Table) -> Vec<i64> {
    let mut widths = Vec::new();
    for c in 0..t.ncols {
        let mut w = 0;
        for row in &t.rows {
            let len = Table::cell(row, c).len() as i64;
            if len > w {
                w = len;
            }
        }
        if w < 1 {
            w = 1;
        }
        widths.push(w);
    }
    widths
}

// A column is numeric when it has a non-empty data cell and every
// non-empty data cell is a number (the header does not count).
pub fn numeric_columns(t: &Table) -> Vec<bool> {
    let mut numeric = Vec::new();
    for c in 0..t.ncols {
        let mut seen = false;
        let mut all = true;
        for row in &t.rows {
            let text = Table::cell(row, c);
            if text.is_empty() {
                continue;
            }
            seen = true;
            if !is_number(text) {
                all = false;
            }
        }
        numeric.push(seen && all);
    }
    numeric
}

fn push_border(out: &mut String, widths: &Vec<i64>) {
    out.push('+');
    for w in widths {
        for _ in 0..*w + 2 {
            out.push('-');
        }
        out.push('+');
    }
    out.push('\n');
}

// `text` padded with spaces to `width`, on the left when `right`.
fn pad_cell(out: &mut String, text: &str, width: i64, right: bool) {
    let pad = width - text.len();
    if !right {
        out.push_string(text);
    }
    for _ in 0..pad {
        out.push(' ');
    }
    if right {
        out.push_str(text);
    }
}

fn push_row(out: &mut String, row: &Vec<String>, widths: &Vec<i64>, numeric: &Vec<bool>) {
    out.push('|');
    for c in 0..widths.len() {
        out.push(' ');
        pad_cell(out, Table::cell(row, c), widths[c]);
        out.push_str(" |");
    }
    out.push('\n');
}

fn render(t: &Table, out: &mut String) {
    let widths = column_widths(t);
    let numeric = numeric_columns(t);
    push_border(out, &widths);
    push_row(out, &t.header, &widths, &numeric);
    push_border(out, &widths);
    for row in &t.rows {
        push_row(out, row, &widths, &numeric);
    }
    if !t.rows.is_empty() {
        push_border(out, &widths);
    }
}
