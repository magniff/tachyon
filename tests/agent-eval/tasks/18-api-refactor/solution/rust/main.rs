// A warehouse robot: reads a map and then commands from stdin, moves the
// robot around (pushing boxes, taking teleporters), and prints what the
// commands ask for. Everything printed goes through `out`.

mod grid;
mod level;
mod report;
mod world;

use grid::{in_bounds, partner, push_pos, step, tile_at, Pos};
use level::{load_level, Level};
use report::{push_load_error, push_map, push_status, push_summary};
use std::io::Read;
use std::io::Write;
use world::{Step, World};

// One command line, parsed.
enum Command<'a> {
    // A blank line or a comment.
    Skip,
    // A line that is not a command: the message after "line N: ".
    Fail(&'static str),
    Unknown(&'a [u8]),
    // A direction and a count.
    Move(u8, i64),
    Undo(i64),
    Reset,
    Where,
    Boxes,
    Mark,
    Marks,
    Dist(Pos),
    Goto(i64),
    History,
    Show,
    Status,
}

// The input's lines, without their line ends ("\n" or "\r\n").
fn split_lines(text: &[u8]) -> Vec<&[u8]> {
    let mut lines: Vec<&[u8]> = Vec::new();
    let mut start = 0;
    for i in 0..text.len() + 1 {
        if i == text.len() || text[i] == b'\n' {
            if i == text.len() && start == i {
                break;
            }
            let mut end = i;
            if end > start && text[end - 1] == b'\r' {
                end -= 1;
            }
            lines.push(&text[start..end]);
            start = i + 1;
        }
    }
    lines
}

// A number of 1 to 9 digits, or -1.
fn parse_num(word: &[u8]) -> i64 {
    if word.is_empty() || word.len() > 9 {
        return -1;
    }
    let mut n: i64 = 0;
    for &ch in word {
        if ch < b'0' || ch > b'9' {
            return -1;
        }
        n = n * 10 + (ch - b'0') as i64;
    }
    n
}

// The optional count of a move or UNDO (1 when there is none), or why
// it is bad.
fn parse_count(words: &Vec<&[u8]>) -> Result<i64, &'static str> {
    if words.len() > 2 {
        return Err("bad arguments");
    }
    if words.len() == 1 {
        return Ok(1);
    }
    let count = parse_num(words[1]);
    if count < 1 {
        return Err("bad count");
    }
    Ok(count)
}

// Turns a line into a command.
fn parse_command<'a>(level: &Level, line: &'a [u8]) -> Command<'a> {
    // The words, separated by runs of spaces.
    let mut words: Vec<&[u8]> = Vec::new();
    let mut i = 0;
    while i < line.len() {
        if line[i] == b' ' {
            i += 1;
            continue;
        }
        let start = i;
        while i < line.len() && line[i] != b' ' {
            i += 1;
        }
        words.push(&line[start..i]);
    }
    if words.is_empty() || words[0][0] == b'#' {
        return Command::Skip;
    }
    let cmd = words[0];
    let nargs = words.len() - 1;
    if cmd == b"N" || cmd == b"S" || cmd == b"E" || cmd == b"W" {
        return match parse_count(&words) {
            Ok(n) => Command::Move(cmd[0], n),
            Err(m) => Command::Fail(m),
        };
    }
    if cmd == b"UNDO" {
        return match parse_count(&words) {
            Ok(n) => Command::Undo(n),
            Err(m) => Command::Fail(m),
        };
    }
    if cmd == b"DIST" {
        if nargs != 2 {
            return Command::Fail("bad arguments");
        }
        let target = Pos::new(parse_num(words[1]), parse_num(words[2]));
        if target.row < 0 || target.col < 0 || !in_bounds(level, target) {
            return Command::Fail("bad position");
        }
        return Command::Dist(target);
    }
    if cmd == b"GOTO" {
        if nargs != 1 {
            return Command::Fail("bad arguments");
        }
        let k = parse_num(words[1]);
        if k < 0 {
            return Command::Fail("bad arguments");
        }
        return Command::Goto(k);
    }
    let plain = if cmd == b"RESET" {
        Command::Reset
    } else if cmd == b"WHERE" {
        Command::Where
    } else if cmd == b"BOXES" {
        Command::Boxes
    } else if cmd == b"MARK" {
        Command::Mark
    } else if cmd == b"MARKS" {
        Command::Marks
    } else if cmd == b"HISTORY" {
        Command::History
    } else if cmd == b"SHOW" {
        Command::Show
    } else if cmd == b"STATUS" {
        Command::Status
    } else {
        return Command::Unknown(cmd);
    };
    if nargs != 0 {
        return Command::Fail("bad arguments");
    }
    plain
}

// The commands that move the robot or the boxes: the moves, UNDO, RESET
// and GOTO. Returns false if `cmd` is not one of them.
fn apply_move(level: &Level, world: &mut World, cmd: &Command, number: i64, out: &mut String) -> bool {
    match *cmd {
        Command::Move(dir, count) => {
            // Up to `count` steps; the first blocked step ends the command.
            let mut done = 0;
            while done < count {
                let next = step(world.robot, dir);
                if tile_at(level, next) == b'#' {
                    break;
                }
                let b = world.box_at(next);
                if b >= 0 {
                    let beyond = step(next, dir);
                    if tile_at(level, beyond) == b'#' || world.box_at(beyond) >= 0 {
                        break;
                    }
                    world.history.push(Step { robot: world.robot, moved_box: b, box_from: next });
                    world.boxes[b as usize] = beyond;
                    world.pushes += 1;
                } else {
                    world.history.push(Step { robot: world.robot, moved_box: -1, box_from: Pos::new(0, 0) });
                }
                world.robot = next;
                if tile_at(level, next) == b'T' {
                    let other = partner(level, next);
                    if world.box_at(other) < 0 {
                        world.robot = other;
                    }
                }
                world.moves += 1;
                done += 1;
            }
            if done < count {
                out.push_str(&format!("line {}: blocked after {} of {} at ", number, done, count));
                push_pos(out, world.robot);
                out.push('\n');
            }
        }
        Command::Undo(count) => {
            // Takes back up to `count` steps, newest first.
            if world.history.is_empty() {
                out.push_str(&format!("line {}: nothing to undo\n", number));
                return true;
            }
            let mut undone = 0;
            while undone < count {
                let s = match world.history.pop() {
                    Some(s) => s,
                    None => break,
                };
                world.robot = s.robot;
                if s.moved_box >= 0 {
                    world.boxes[s.moved_box as usize] = s.box_from;
                    world.pushes -= 1;
                }
                world.moves -= 1;
                undone += 1;
            }
        }
        Command::Reset => world.reset(level),
        Command::Goto(k) => {
            // Walks to a mark by a shortest path; the walk cannot be undone.
            if k < 1 || k > world.marks.len() as i64 {
                out.push_str(&format!("line {}: no mark {}\n", number, k));
                return true;
            }
            let target = world.marks[(k - 1) as usize];
            let d = world.distance(level, world.robot, target);
            if d < 0 {
                out.push_str(&format!("goto {}: unreachable\n", k));
                return true;
            }
            world.robot = target;
            world.moves += d;
            world.history.clear();
            out.push_str(&format!("goto {}: {} moves\n", k, d));
        }
        _ => return false,
    }
    true
}

// The commands that only look (and MARK, which only remembers).
fn apply_query(level: &Level, world: &mut World, cmd: &Command, out: &mut String) {
    match *cmd {
        Command::Where => {
            out.push_str("robot at ");
            push_pos(out, world.robot);
            out.push('\n');
        }
        Command::Boxes => {
            // Sorted by row, then column.
            out.push_str("boxes:");
            if world.boxes.is_empty() {
                out.push_str(" none");
            }
            let mut keys: Vec<i64> = Vec::new();
            for k in 0..world.boxes.len() {
                let b = world.boxes[k];
                keys.push(b.row * level.width + b.col);
            }
            keys.sort();
            for k in 0..keys.len() {
                out.push(' ');
                push_pos(out, Pos::new(keys[k] / level.width, keys[k] % level.width));
            }
            out.push('\n');
        }
        Command::Mark => {
            world.marks.push(world.robot);
            out.push_str(&format!("mark {} at ", world.marks.len()));
            push_pos(out, world.robot);
            out.push('\n');
        }
        Command::Marks => {
            out.push_str("marks:");
            if world.marks.is_empty() {
                out.push_str(" none");
            }
            for k in 0..world.marks.len() {
                out.push_str(&format!(" {}=", k + 1));
                push_pos(out, world.marks[k]);
            }
            out.push('\n');
        }
        Command::Dist(target) => {
            // The fewest steps from the robot to a row and column.
            let d = world.distance(level, world.robot, target);
            out.push_str("dist ");
            push_pos(out, target);
            if d < 0 {
                out.push_str(": unreachable\n");
            } else {
                out.push_str(&format!(": {}\n", d));
            }
        }
        Command::History => out.push_str(&format!("history {}\n", world.history.len())),
        Command::Show => push_map(out, level, world),
        Command::Status => push_status(out, level, world),
        _ => {}
    }
}

// Runs the commands: the lines after the map's '---' line. `first` is
// the index of the first of them in `lines`; line numbers in messages
// count every line of the input from 1.
fn run_commands(level: &Level, world: &mut World, lines: &[&[u8]], first: usize, out: &mut String) {
    for li in first..lines.len() {
        let number = li as i64 + 1;
        let cmd = parse_command(level, lines[li]);
        match cmd {
            Command::Skip => {}
            Command::Fail(m) => out.push_str(&format!("line {}: {}\n", number, m)),
            Command::Unknown(w) => {
                out.push_str(&format!("line {}: unknown command '", number));
                out.push_str(&String::from_utf8_lossy(w));
                out.push_str("'\n");
            }
            _ => {
                if !apply_move(level, world, &cmd, number, out) {
                    apply_query(level, world, &cmd, out);
                }
            }
        }
    }
}

fn main() {
    let mut input: Vec<u8> = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    let lines = split_lines(&input);
    let mut out = String::new();
    match load_level(&lines) {
        Err(e) => push_load_error(&mut out, &e),
        Ok(level) => {
            push_summary(&mut out, &level);
            let mut world = World::new(&level);
            run_commands(&level, &mut world, &lines, level.map_lines as usize + 1, &mut out);
            out.push_str("final: ");
            push_status(&mut out, &level, &world);
        }
    }
    std::io::stdout().write_all(out.as_bytes()).unwrap();
}
