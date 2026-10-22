//! The oracle of examples/voltty/core: alacritty_terminal (the crate Alacritty
//! 0.17.0 is built on) fed the same bytes as the vole terminal, its
//! state printed in the dump format of FORMAT.md.
//!
//! usage:
//!   voltty-oracle dump LINES COLS HISTORY < bytes      one terminal, one dump
//!   voltty-oracle script < script                      the script format (FORMAT.md)
//!   voltty-oracle bench [-n RUNS] FILE...              parse + grid throughput
//!   voltty-oracle width-table                          unicode-width's char widths, as ranges
//!   voltty-oracle version

use std::cell::RefCell;
use std::io::{self, Read, Write};
use std::rc::Rc;
use std::time::Instant;

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::grid::Dimensions;
use alacritty_terminal::index::{Column, Line};
use alacritty_terminal::term::cell::Cell;
use alacritty_terminal::term::test::TermSize;
use alacritty_terminal::term::{ClipboardType, Config, Term};
use alacritty_terminal::vte::ansi::{
    CharsetIndex, Color, CursorShape, Processor, Rgb, StandardCharset,
};

/// The events a dump reports: replies, the title, clipboard stores.
#[derive(Default)]
struct Events {
    reply: Vec<u8>,
    title: Option<String>,
    clip: Vec<(u8, String)>,
    /// Colour queries: where in `reply`, the colour, the formatter. The
    /// window answers them after the parser's batch (Alacritty's event
    /// loop), with the colours as they are then.
    colors: Vec<(usize, usize, ColorFn)>,
}

type ColorFn = std::sync::Arc<dyn Fn(Rgb) -> String + Sync + Send + 'static>;

/// The palette a colour query reports when no OSC set the colour (the
/// same as examples/voltty/core's `default_color`): Alacritty's default colours,
/// the 6x6x6 cube, the grey ramp.
fn default_color(index: usize) -> Rgb {
    const BASE: [u32; 16] = [
        0x181818, 0xAC4242, 0x90A959, 0xF4BF75, 0x6A9FB5, 0xAA759F, 0x75B5AA, 0xD8D8D8, 0x6B6B6B,
        0xC55555, 0xAAC474, 0xFECA88, 0x82B8C8, 0xC28CB8, 0x93D3C3, 0xF8F8F8,
    ];
    let v = if index < 16 {
        BASE[index]
    } else if index < 232 {
        let i = index - 16;
        let cube = |v: usize| if v == 0 { 0 } else { v * 40 + 55 } as u32;
        (cube(i / 36) << 16) | (cube((i / 6) % 6) << 8) | cube(i % 6)
    } else if index < 256 {
        let g = ((index - 232) * 10 + 8) as u32;
        (g << 16) | (g << 8) | g
    } else if index == 257 {
        0x181818
    } else {
        0xD8D8D8
    };
    Rgb { r: (v >> 16) as u8, g: (v >> 8) as u8, b: v as u8 }
}

#[derive(Clone, Default)]
struct Listener(Rc<RefCell<Events>>);

impl EventListener for Listener {
    fn send_event(&self, event: Event) {
        let mut e = self.0.borrow_mut();
        match event {
            Event::PtyWrite(text) => e.reply.extend_from_slice(text.as_bytes()),
            Event::ColorRequest(index, f) => {
                let at = e.reply.len();
                e.colors.push((at, index, f));
            },
            Event::Title(t) => e.title = Some(t),
            Event::ResetTitle => e.title = None,
            Event::ClipboardStore(ty, text) => {
                let c = if ty == ClipboardType::Clipboard { b'c' } else { b's' };
                e.clip.push((c, text));
            },
            _ => (),
        }
    }
}

struct Session {
    term: Term<Listener>,
    parser: Processor,
    events: Listener,
}

impl Session {
    fn new(lines: usize, cols: usize, history: usize) -> Session {
        let events = Listener::default();
        let config = Config { scrolling_history: history, ..Config::default() };
        let term = Term::new(config, &TermSize::new(cols, lines), events.clone());
        Session { term, parser: Processor::new(), events }
    }

    fn feed(&mut self, bytes: &[u8]) {
        self.parser.advance(&mut self.term, bytes);
        self.answer_colors();
    }

    fn answer_colors(&mut self) {
        let mut e = self.events.0.borrow_mut();
        if e.colors.is_empty() {
            return;
        }
        let queries = std::mem::take(&mut e.colors);
        let old = std::mem::take(&mut e.reply);
        let mut at = 0;
        for (pos, index, f) in queries {
            e.reply.extend_from_slice(&old[at..pos]);
            at = pos;
            let rgb = self.term.colors()[index].unwrap_or_else(|| default_color(index));
            e.reply.extend_from_slice(f(rgb).as_bytes());
        }
        e.reply.extend_from_slice(&old[at..]);
    }

    fn resize(&mut self, lines: usize, cols: usize) {
        self.term.resize(TermSize::new(cols, lines));
    }

    /// A synchronized update (mode 2026) only holds rendering: the dump
    /// shows the state with the held bytes applied.
    fn settle(&mut self) {
        if self.parser.sync_bytes_count() > 0 || self.parser.sync_timeout().sync_timeout().is_some() {
            self.parser.stop_sync(&mut self.term);
            self.answer_colors();
        }
    }

    fn dump(&mut self, out: &mut Vec<u8>) {
        self.settle();
        let term = &self.term;
        let grid = term.grid();
        let lines = grid.screen_lines();
        let cols = grid.columns();
        let _ = writeln!(out, "size {lines} {cols}");
        let c = &grid.cursor;
        let _ = writeln!(
            out,
            "cursor {} {} {}",
            c.point.line.0,
            c.point.column.0,
            c.input_needs_wrap as u8
        );
        let style = term.cursor_style();
        let shape = match style.shape {
            CursorShape::Block => "block",
            CursorShape::Underline => "underline",
            CursorShape::Beam => "beam",
            CursorShape::HollowBlock => "hollow",
            CursorShape::Hidden => "hidden",
        };
        let _ = writeln!(out, "style {} {}", shape, style.blinking as u8);
        let _ = writeln!(out, "mode {:x}", term.mode().bits());
        {
            let e = self.events.0.borrow();
            match &e.title {
                Some(t) => {
                    out.extend_from_slice(b"title ");
                    escape_bytes(out, t.as_bytes());
                    out.push(b'\n');
                },
                None => out.extend_from_slice(b"title -\n"),
            }
        }
        out.extend_from_slice(b"tmpl ");
        cell_attrs(out, &c.template);
        out.push(b'\n');
        out.extend_from_slice(b"charsets ");
        charsets(out, c);
        out.push(b'\n');
        let s = &grid.saved_cursor;
        let _ = write!(
            out,
            "saved {} {} {} ",
            s.point.line.0,
            s.point.column.0,
            s.input_needs_wrap as u8
        );
        cell_attrs(out, &s.template);
        out.push(b' ');
        charsets(out, s);
        out.push(b'\n');
        let colors = term.colors();
        for i in 0..alacritty_terminal::term::color::COUNT {
            if let Some(rgb) = colors[i] {
                let _ = writeln!(out, "color {} #{:02x}{:02x}{:02x}", i, rgb.r, rgb.g, rgb.b);
            }
        }
        {
            let mut e = self.events.0.borrow_mut();
            if !e.reply.is_empty() {
                out.extend_from_slice(b"reply ");
                let reply = std::mem::take(&mut e.reply);
                escape_bytes(out, &reply);
                out.push(b'\n');
            }
            for (ty, text) in std::mem::take(&mut e.clip) {
                let _ = write!(out, "clip {} ", ty as char);
                escape_bytes(out, text.as_bytes());
                out.push(b'\n');
            }
        }
        let history = grid.history_size();
        let _ = writeln!(out, "history {history}");
        let top = -(history as i32);
        for l in top..lines as i32 {
            let row = &grid[Line(l)];
            // The text, without the trailing blank default cells.
            let mut end = cols;
            while end > 0 && is_blank(&row[Column(end - 1)]) {
                end -= 1;
            }
            let _ = write!(out, "row {l} ");
            for x in 0..end {
                let cell = &row[Column(x)];
                escape_char(out, cell.c);
                if let Some(zw) = cell.zerowidth() {
                    for z in zw {
                        let _ = write!(out, "\\+{{{:x}}}", *z as u32);
                    }
                }
            }
            out.push(b'\n');
            // The runs of cells whose attributes are not the default's.
            let mut x = 0;
            while x < cols {
                let mut a = Vec::new();
                cell_attrs(&mut a, &row[Column(x)]);
                if a == DEFAULT_ATTRS.as_bytes() {
                    x += 1;
                    continue;
                }
                let mut y = x + 1;
                while y < cols {
                    let mut b = Vec::new();
                    cell_attrs(&mut b, &row[Column(y)]);
                    if b != a {
                        break;
                    }
                    y += 1;
                }
                let _ = write!(out, "attr {} {}-{} ", l, x, y - 1);
                out.extend_from_slice(&a);
                out.push(b'\n');
                x = y;
            }
        }
        out.extend_from_slice(b"end\n");
    }
}

const DEFAULT_ATTRS: &str = "n256 n257 0 - -";

fn is_blank(cell: &Cell) -> bool {
    let mut a = Vec::new();
    cell_attrs(&mut a, cell);
    cell.c == ' ' && cell.zerowidth().is_none_or(|z| z.is_empty()) && a == DEFAULT_ATTRS.as_bytes()
}

fn color(out: &mut Vec<u8>, c: Color) {
    let _ = match c {
        Color::Named(n) => write!(out, "n{}", n as usize),
        Color::Indexed(i) => write!(out, "i{i}"),
        Color::Spec(rgb) => write!(out, "#{:02x}{:02x}{:02x}", rgb.r, rgb.g, rgb.b),
    };
}

/// `fg bg flags ul link`: the attributes of a cell (or the template).
fn cell_attrs(out: &mut Vec<u8>, cell: &Cell) {
    color(out, cell.fg);
    out.push(b' ');
    color(out, cell.bg);
    let _ = write!(out, " {:x} ", cell.flags.bits());
    match cell.underline_color() {
        Some(c) => color(out, c),
        None => out.push(b'-'),
    }
    out.push(b' ');
    match cell.hyperlink() {
        Some(link) => {
            let id = link.id();
            if id.ends_with("_alacritty") {
                out.push(b'*');
            } else {
                escape_bytes(out, id.as_bytes());
            }
            out.push(b'|');
            escape_bytes(out, link.uri().as_bytes());
        },
        None => out.push(b'-'),
    }
}

fn charsets<T>(out: &mut Vec<u8>, c: &alacritty_terminal::grid::Cursor<T>) {
    for i in [CharsetIndex::G0, CharsetIndex::G1, CharsetIndex::G2, CharsetIndex::G3] {
        out.push(match c.charsets[i] {
            StandardCharset::Ascii => b'a',
            StandardCharset::SpecialCharacterAndLineDrawing => b'g',
        });
    }
}

/// A cell's character: printable ASCII as itself (but `\`), U+00A0 and
/// above as UTF-8, the rest `\u{X}`.
fn escape_char(out: &mut Vec<u8>, c: char) {
    let u = c as u32;
    if (0x20..0x7f).contains(&u) && c != '\\' {
        out.push(u as u8);
    } else if u >= 0xa0 {
        let mut b = [0u8; 4];
        out.extend_from_slice(c.encode_utf8(&mut b).as_bytes());
    } else {
        let _ = write!(out, "\\u{{{u:x}}}");
    }
}

/// Bytes: printable ASCII as itself (but `\`), the rest `\xNN`.
fn escape_bytes(out: &mut Vec<u8>, s: &[u8]) {
    for &b in s {
        if (0x20..0x7f).contains(&b) && b != b'\\' {
            out.push(b);
        } else {
            let _ = write!(out, "\\x{b:02x}");
        }
    }
}

fn read_stdin() -> Vec<u8> {
    let mut v = Vec::new();
    io::stdin().read_to_end(&mut v).expect("stdin");
    v
}

fn num(s: &str) -> usize {
    s.trim().parse().unwrap_or_else(|_| {
        eprintln!("voltty-oracle: not a number: {s:?}");
        std::process::exit(2)
    })
}

/// The script format: lines `T lines cols history`, `D n` (then n raw
/// bytes), `R lines cols`, `P` (print a dump); see FORMAT.md.
fn run_script(input: &[u8], out: &mut Vec<u8>) {
    let mut at = 0;
    let mut session: Option<Session> = None;
    while at < input.len() {
        let nl = match input[at..].iter().position(|&b| b == b'\n') {
            Some(n) => at + n,
            None => input.len(),
        };
        let line = std::str::from_utf8(&input[at..nl]).unwrap_or("");
        at = nl + 1;
        let mut words = line.split(' ');
        match words.next() {
            Some("T") => {
                let l = num(words.next().unwrap_or(""));
                let c = num(words.next().unwrap_or(""));
                let h = num(words.next().unwrap_or(""));
                session = Some(Session::new(l, c, h));
            },
            Some("D") => {
                let n = num(words.next().unwrap_or(""));
                let end = (at + n).min(input.len());
                if let Some(s) = session.as_mut() {
                    s.feed(&input[at..end]);
                }
                at = end;
            },
            Some("R") => {
                let l = num(words.next().unwrap_or(""));
                let c = num(words.next().unwrap_or(""));
                if let Some(s) = session.as_mut() {
                    s.settle();
                    s.resize(l, c);
                }
            },
            Some("P") => {
                if let Some(s) = session.as_mut() {
                    s.dump(out);
                }
            },
            Some("") | None => (),
            Some(other) => {
                eprintln!("voltty-oracle: unknown script command {other:?}");
                std::process::exit(2);
            },
        }
    }
}

fn bench(args: &[String]) {
    let mut runs = 5;
    let mut files = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "-n" && i + 1 < args.len() {
            runs = num(&args[i + 1]);
            i += 2;
        } else {
            files.push(args[i].clone());
            i += 1;
        }
    }
    for f in files {
        let data = std::fs::read(&f).unwrap_or_else(|e| {
            eprintln!("voltty-oracle: {f}: {e}");
            std::process::exit(2)
        });
        let mut best = f64::MAX;
        for _ in 0..runs {
            let mut s = Session::new(40, 120, 10000);
            let t0 = Instant::now();
            for chunk in data.chunks(65536) {
                s.feed(chunk);
            }
            let t = t0.elapsed().as_secs_f64();
            std::hint::black_box(&s.term);
            if t < best {
                best = t;
            }
        }
        let mb = data.len() as f64 / (1024.0 * 1024.0);
        println!("{f}: {:.1} MiB in {:.1} ms, {:.0} MiB/s", mb, best * 1000.0, mb / best);
    }
}

/// unicode-width 0.2.2's `width()` of every char, as ranges `lo hi w`
/// (w: 0, 1, 2, or n for None); the generator of term/width.vl reads it.
fn width_table() {
    use unicode_width::UnicodeWidthChar;
    let code = |w: Option<usize>| match w {
        None => 'n',
        Some(0) => '0',
        Some(1) => '1',
        Some(_) => '2',
    };
    let mut start = 0u32;
    let mut cur = code('\0'.width());
    let mut out = String::new();
    for u in 1..=0x10FFFFu32 {
        let w = match char::from_u32(u) {
            Some(c) => code(c.width()),
            None => '1', // surrogates never reach the terminal
        };
        if w != cur {
            out.push_str(&format!("{start:x} {:x} {cur}\n", u - 1));
            start = u;
            cur = w;
        }
    }
    out.push_str(&format!("{start:x} 10ffff {cur}\n"));
    print!("{out}");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut out = Vec::new();
    match args.get(1).map(|s| s.as_str()) {
        Some("dump") if args.len() == 5 => {
            let mut s = Session::new(num(&args[2]), num(&args[3]), num(&args[4]));
            s.feed(&read_stdin());
            s.dump(&mut out);
        },
        Some("script") => run_script(&read_stdin(), &mut out),
        Some("bench") => bench(&args[2..]),
        Some("width-table") => width_table(),
        Some("version") => println!("alacritty_terminal 0.26.0 (Alacritty 0.17.0), unicode-width 0.2.2"),
        _ => {
            eprintln!("usage: voltty-oracle dump LINES COLS HISTORY | script | bench [-n RUNS] FILE... | width-table | version");
            std::process::exit(2);
        },
    }
    let _ = io::stdout().write_all(&out);
}
