// A warehouse robot: reads a map and then commands from stdin, moves the
// robot around (pushing boxes, taking teleporters), and prints what the
// commands ask for. Everything printed goes through `out`.

mod grid;
mod level;
mod report;
mod world;

use grid::{in_bounds, partner, push_pos, step, tile_at};
use level::{load_level, Level};
use report::{push_load_error, push_map, push_status, push_summary};
use std::io::Read;
use std::io::Write;
use world::{Step, World};

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

// Runs the commands: the lines after the map's '---' line. `first` is
// the index of the first of them in `lines`; line numbers in messages
// count every line of the input from 1.
fn run_commands(level: &Level, world: &mut World, lines: &[&[u8]], first: usize, out: &mut String) {
    for li in first..lines.len() {
        let line = lines[li];
        let number = li as i64 + 1;
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
            continue;
        }
        let cmd = words[0];
        let nargs = words.len() - 1;
        if cmd == b"N" || cmd == b"S" || cmd == b"E" || cmd == b"W" {
            // Up to `count` steps; the first blocked step ends the command.
            if nargs > 1 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            let mut count = 1;
            if nargs == 1 {
                count = parse_num(words[1]);
                if count < 1 {
                    out.push_str(&format!("line {}: bad count\n", number));
                    continue;
                }
            }
            let dir = cmd[0];
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
                    world.history.push(Step { robot: world.robot, moved_box: -1, box_from: (0, 0) });
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
        } else if cmd == b"UNDO" {
            // Takes back up to `count` steps, newest first.
            if nargs > 1 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            let mut count = 1;
            if nargs == 1 {
                count = parse_num(words[1]);
                if count < 1 {
                    out.push_str(&format!("line {}: bad count\n", number));
                    continue;
                }
            }
            if world.history.is_empty() {
                out.push_str(&format!("line {}: nothing to undo\n", number));
                continue;
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
        } else if cmd == b"RESET" {
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            world.reset(level);
        } else if cmd == b"WHERE" {
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            out.push_str("robot at ");
            push_pos(out, world.robot);
            out.push('\n');
        } else if cmd == b"BOXES" {
            // Sorted by row, then column.
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            out.push_str("boxes:");
            if world.boxes.is_empty() {
                out.push_str(" none");
            }
            let mut keys: Vec<i64> = Vec::new();
            for k in 0..world.boxes.len() {
                let b = world.boxes[k];
                keys.push(b.0 * level.width + b.1);
            }
            keys.sort();
            for k in 0..keys.len() {
                let p = (keys[k] / level.width, keys[k] % level.width);
                out.push(' ');
                push_pos(out, p);
            }
            out.push('\n');
        } else if cmd == b"MARK" {
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            world.marks.push(world.robot);
            out.push_str(&format!("mark {} at ", world.marks.len()));
            push_pos(out, world.robot);
            out.push('\n');
        } else if cmd == b"MARKS" {
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            out.push_str("marks:");
            if world.marks.is_empty() {
                out.push_str(" none");
            }
            for k in 0..world.marks.len() {
                out.push_str(&format!(" {}=", k + 1));
                push_pos(out, world.marks[k]);
            }
            out.push('\n');
        } else if cmd == b"DIST" {
            // The fewest steps from the robot to a row and column.
            if nargs != 2 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            let r = parse_num(words[1]);
            let c = parse_num(words[2]);
            let target = (r, c);
            if r < 0 || c < 0 || !in_bounds(level, target) {
                out.push_str(&format!("line {}: bad position\n", number));
                continue;
            }
            let d = world.distance(level, world.robot, target);
            out.push_str("dist ");
            push_pos(out, target);
            if d < 0 {
                out.push_str(": unreachable\n");
            } else {
                out.push_str(&format!(": {}\n", d));
            }
        } else if cmd == b"GOTO" {
            // Walks to a mark by a shortest path; the walk cannot be undone.
            if nargs != 1 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            let k = parse_num(words[1]);
            if k < 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            if k < 1 || k > world.marks.len() as i64 {
                out.push_str(&format!("line {}: no mark {}\n", number, k));
                continue;
            }
            let target = world.marks[(k - 1) as usize];
            let d = world.distance(level, world.robot, target);
            if d < 0 {
                out.push_str(&format!("goto {}: unreachable\n", k));
                continue;
            }
            world.robot = target;
            world.moves += d;
            world.history.clear();
            out.push_str(&format!("goto {}: {} moves\n", k, d));
        } else if cmd == b"HISTORY" {
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            out.push_str(&format!("history {}\n", world.history.len()));
        } else if cmd == b"SHOW" {
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            push_map(out, level, world);
        } else if cmd == b"STATUS" {
            if nargs != 0 {
                out.push_str(&format!("line {}: bad arguments\n", number));
                continue;
            }
            push_status(out, level, world);
        } else {
            out.push_str(&format!("line {}: unknown command '", number));
            out.push_str(&String::from_utf8_lossy(cmd));
            out.push_str("'\n");
        }
    }
}

fn main() {
    let mut input: Vec<u8> = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    let lines = split_lines(&input);
    let mut out = String::new();
    let mut level = Level::new();
    let code = load_level(&lines, &mut level);
    if code != 0 {
        push_load_error(&mut out, code, &level);
    } else {
        push_summary(&mut out, &level);
        let mut world = World::new(&level);
        run_commands(&level, &mut world, &lines, level.map_lines as usize + 1, &mut out);
        out.push_str("final: ");
        push_status(&mut out, &level, &world);
    }
    std::io::stdout().write_all(out.as_bytes()).unwrap();
}
