// The table: its header and rows, read from the CSV part of the input.

#[derive(Clone, Copy, PartialEq)]
pub enum ColType {
    Int,
    Str,
}

#[derive(Clone, PartialEq)]
pub enum Value {
    Null,
    Int(i64),
    Str(Vec<u8>),
}

pub struct Table {
    pub names: Vec<Vec<u8>>,
    pub types: Vec<ColType>,
    // Row r, column c is cells[r * ncols + c].
    pub cells: Vec<Value>,
    pub nrows: usize,
}

impl Table {
    pub fn ncols(&self) -> usize {
        self.names.len()
    }

    pub fn cell(&self, row: usize, col: usize) -> &Value {
        &self.cells[row * self.names.len() + col]
    }

    pub fn find(&self, name: &[u8]) -> Option<usize> {
        for i in 0..self.names.len() {
            if self.names[i] == name {
                return Some(i);
            }
        }
        None
    }
}

pub fn is_null(v: &Value) -> bool {
    match v {
        Value::Null => true,
        _ => false,
    }
}

// Negative, zero or positive; NULL is smaller than everything.
pub fn compare(a: &Value, b: &Value) -> i32 {
    match (a, b) {
        (Value::Null, Value::Null) => 0,
        (Value::Null, _) => -1,
        (_, Value::Null) => 1,
        (Value::Int(x), Value::Int(y)) => {
            if x < y {
                -1
            } else if x > y {
                1
            } else {
                0
            }
        }
        (Value::Str(x), Value::Str(y)) => compare_bytes(x, y),
        (Value::Int(_), Value::Str(_)) => -1,
        (Value::Str(_), Value::Int(_)) => 1,
    }
}

pub fn compare_bytes(a: &[u8], b: &[u8]) -> i32 {
    let n = if a.len() < b.len() { a.len() } else { b.len() };
    for i in 0..n {
        if a[i] != b[i] {
            return if a[i] < b[i] { -1 } else { 1 };
        }
    }
    if a.len() < b.len() {
        -1
    } else if a.len() > b.len() {
        1
    } else {
        0
    }
}

pub fn parse_int(s: &[u8]) -> i64 {
    let mut i = 0;
    let mut neg = false;
    if i < s.len() && s[i] == b'-' {
        neg = true;
        i += 1;
    }
    let mut v: i64 = 0;
    while i < s.len() {
        v = v * 10 + (s[i] - b'0') as i64;
        i += 1;
    }
    if neg {
        -v
    } else {
        v
    }
}

// Splits one CSV line into its fields, unquoting the quoted ones.
fn split_fields(line: &[u8]) -> Vec<Vec<u8>> {
    let mut fields = Vec::new();
    let mut i = 0;
    loop {
        let mut field = Vec::new();
        if i < line.len() && line[i] == b'"' {
            i += 1;
            while i < line.len() {
                if line[i] == b'"' {
                    if i + 1 < line.len() && line[i + 1] == b'"' {
                        field.push(b'"');
                        i += 2;
                    } else {
                        i += 1;
                        break;
                    }
                } else {
                    field.push(line[i]);
                    i += 1;
                }
            }
        } else {
            while i < line.len() && line[i] != b',' {
                field.push(line[i]);
                i += 1;
            }
        }
        fields.push(field);
        if i < line.len() && line[i] == b',' {
            i += 1;
        } else {
            break;
        }
    }
    fields
}

// Reads the header and the rows from `lines`, up to the line `%%`; returns
// the table and the index of the first line after `%%`.
pub fn read_table(lines: &[&[u8]]) -> (Table, usize) {
    let mut t = Table {
        names: Vec::new(),
        types: Vec::new(),
        cells: Vec::new(),
        nrows: 0,
    };
    let mut k = 0;
    if !lines.is_empty() {
        for item in split_fields(lines[0]) {
            let mut colon = item.len();
            for j in 0..item.len() {
                if item[j] == b':' {
                    colon = j;
                    break;
                }
            }
            t.names.push(item[..colon].to_vec());
            let ty = &item[colon + 1..];
            t.types.push(if ty == b"int" {
                ColType::Int
            } else {
                ColType::Str
            });
        }
        k = 1;
    }
    while k < lines.len() {
        let line = lines[k];
        k += 1;
        if line == b"%%" {
            break;
        }
        if line.is_empty() {
            continue;
        }
        let fields = split_fields(line);
        for c in 0..t.ncols() {
            let text = &fields[c];
            let v = if t.types[c] == ColType::Int {
                if text.is_empty() {
                    Value::Null
                } else {
                    Value::Int(parse_int(text))
                }
            } else {
                Value::Str(text.clone())
            };
            t.cells.push(v);
        }
        t.nrows += 1;
    }
    (t, k)
}
