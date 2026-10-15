// The table: a header row and data rows of text cells, read from
// comma-separated lines.

pub struct Table {
    pub header: Vec<String>,
    pub rows: Vec<Vec<String>>,
    // The number of columns: the most fields on any line.
    pub ncols: usize,
}

impl Table {
    // Cell `col` of `row`, or "" when the row is shorter.
    pub fn cell(row: &Vec<String>, col: usize) -> &str {
        if col < row.len() {
            &row[col]
        } else {
            ""
        }
    }
}

fn is_blank(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r'
}

// `s` without blanks at either end.
fn trim(s: &[u8]) -> &[u8] {
    let mut lo = 0;
    let mut hi = s.len();
    while lo < hi && is_blank(s[lo]) {
        lo += 1;
    }
    while hi > lo && is_blank(s[hi - 1]) {
        hi -= 1;
    }
    &s[lo..hi]
}

// The fields of one line, split at commas and trimmed.
fn split_line(line: &[u8]) -> Vec<String> {
    let mut fields = Vec::new();
    let mut start = 0;
    for i in 0..line.len() + 1 {
        if i == line.len() || line[i] == b',' {
            let field = trim(&line[start..i]);
            fields.push(String::from_utf8_lossy(field).to_string());
            start = i + 1;
        }
    }
    fields
}

// The first non-blank line is the header; the other non-blank lines are rows.
pub fn parse_table(text: &[u8]) -> Table {
    let mut t = Table {
        header: Vec::new(),
        rows: Vec::new(),
        ncols: 0,
    };
    let mut have_header = false;
    let mut start = 0;
    for i in 0..text.len() + 1 {
        if i == text.len() || text[i] == b'\n' {
            let line = &text[start..i];
            start = i + 1;
            if trim(line).is_empty() {
                continue;
            }
            let fields = split_line(line);
            if fields.len() > t.ncols {
                t.ncols = fields.len();
            }
            if have_header {
                t.rows.push(fields);
            } else {
                t.header = fields;
                have_header = true;
            }
        }
    }
    t
}
