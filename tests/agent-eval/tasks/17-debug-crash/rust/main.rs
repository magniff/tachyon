// An event log aggregator: reads events and settings from stdin, one per
// line, groups the events by key and prints a report at the end.

mod report;
mod stats;
mod table;
mod text;

use std::io::{self, Read, Write};

use report::write_report;
use stats::Group;
use table::Table;
use text::{parse_int, split_words};

// Everything read so far.
pub struct State {
    // The settings in effect (the last SPAN, WIDTH and TOP lines).
    pub span: i64,
    pub width: i64,
    pub top: i64,
    // The groups in order of their first event, and the table that finds
    // a key's group.
    pub groups: Vec<Group>,
    pub table: Table,
    // The words of every NOTE line, in order.
    pub notes: Vec<Vec<u8>>,
    pub events: i64,
    pub bad: i64,
    // The time of the last accepted event (0 before the first).
    pub now: i64,
}

impl State {
    fn new() -> State {
        State {
            span: 60,
            width: 40,
            top: 0,
            groups: Vec::new(),
            table: Table::new(),
            notes: Vec::new(),
            events: 0,
            bad: 0,
            now: 0,
        }
    }
}

// SPAN n, WIDTH n (n at least 1) and TOP n (n at least 0); false when
// the line is not a valid setting.
fn handle_setting(st: &mut State, words: &[&[u8]]) -> bool {
    if words.len() != 2 {
        return false;
    }
    let v = match parse_int(words[1]) {
        Some(v) => v,
        None => return false,
    };
    let name = words[0];
    if name == b"TOP" {
        if v < 0 {
            return false;
        }
        st.top = v;
    } else {
        if v < 1 {
            return false;
        }
        if name == b"SPAN" {
            st.span = v;
        } else {
            st.width = v;
        }
    }
    true
}

// TIME KEY VALUE; false when the line is not a valid event.
fn handle_event(st: &mut State, words: &[&[u8]], line_no: i64) -> bool {
    if words.len() != 3 {
        return false;
    }
    let time = match parse_int(words[0]) {
        Some(t) => t,
        None => return false,
    };
    let value = match parse_int(words[2]) {
        Some(v) => v,
        None => return false,
    };
    if time < 0 || time < st.now {
        return false;
    }
    let key = words[1];
    let g = match st.table.get(key) {
        Some(g) => g,
        None => {
            let g = st.groups.len() as i64;
            st.groups.push(Group::new(key, line_no));
            st.table.insert(key, g);
            g
        }
    };
    st.groups[g as usize].add(time, value);
    st.now = time;
    st.events += 1;
    true
}

fn handle_line(st: &mut State, line: &[u8], line_no: i64) {
    let words = split_words(line);
    if words.is_empty() || words[0][0] == b'#' {
        return;
    }
    let first = words[0];
    let ok = if first == b"NOTE" {
        for w in &words[1..] {
            st.notes.push(w.to_vec());
        }
        true
    } else if first == b"SPAN" || first == b"WIDTH" || first == b"TOP" {
        handle_setting(st, &words)
    } else {
        handle_event(st, &words, line_no)
    };
    if !ok {
        st.bad += 1;
    }
}

fn main() {
    let mut input: Vec<u8> = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();
    let mut st = State::new();
    let mut start = 0;
    let mut line_no = 0;
    for i in 0..input.len() + 1 {
        if i == input.len() || input[i] == b'\n' {
            let mut end = i;
            if end > start && input[end - 1] == b'\r' {
                end -= 1;
            }
            line_no += 1;
            handle_line(&mut st, &input[start..end], line_no);
            start = i + 1;
        }
    }
    let mut out: Vec<u8> = Vec::new();
    write_report(&st, &mut out);
    io::stdout().write_all(&out).unwrap();
}
