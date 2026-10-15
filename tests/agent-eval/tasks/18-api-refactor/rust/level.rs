// The level: the map's tiles, where the robot starts, the boxes, the goals
// and the teleporters, and `load_level`, which reads them from the input.

// What load_level returns: 0 when the map is good, else one of these.
pub const ERR_EMPTY: i64 = -1;
pub const ERR_NO_SEPARATOR: i64 = -2;
pub const ERR_RAGGED: i64 = -3;
pub const ERR_UNKNOWN_TILE: i64 = -4;
pub const ERR_NO_ROBOT: i64 = -5;
pub const ERR_MANY_ROBOTS: i64 = -6;
pub const ERR_ODD_TELEPORTERS: i64 = -7;

pub struct Level {
    pub height: i64,
    pub width: i64,
    // Row by row: '#' wall, '.' floor, 'G' goal, 'T' teleporter. The robot
    // and the boxes are not in it: their tiles are floor or goal.
    pub tiles: Vec<u8>,
    pub start: (i64, i64),
    // Each in reading order (row by row, left to right).
    pub boxes: Vec<(i64, i64)>,
    pub goals: Vec<(i64, i64)>,
    pub teleporters: Vec<(i64, i64)>,
    // The number of map lines; the '---' line comes after them.
    pub map_lines: i64,
    // Set by load_level when it fails: the place of the problem (row and
    // column), the tile, and a number (a row's length, a count).
    pub error_at: (i64, i64),
    pub error_tile: u8,
    pub error_num: i64,
}

impl Level {
    pub fn new() -> Level {
        Level {
            height: 0,
            width: 0,
            tiles: Vec::new(),
            start: (0, 0),
            boxes: Vec::new(),
            goals: Vec::new(),
            teleporters: Vec::new(),
            map_lines: 0,
            error_at: (0, 0),
            error_tile: 0,
            error_num: 0,
        }
    }
}

// Reads the map from the input's lines into `dest`: the lines before the
// first '---' line. Returns 0, or an error code with the details of the
// problem in dest's error fields.
pub fn load_level(lines: &[&[u8]], dest: &mut Level) -> i64 {
    let mut sep: i64 = -1;
    for i in 0..lines.len() {
        if lines[i] == b"---" {
            sep = i as i64;
            break;
        }
    }
    if sep < 0 {
        return ERR_NO_SEPARATOR;
    }
    if sep == 0 || lines[0].is_empty() {
        return ERR_EMPTY;
    }
    dest.map_lines = sep;
    dest.height = sep;
    dest.width = lines[0].len() as i64;
    let mut robots = 0;
    for r in 0..sep {
        let row = lines[r as usize];
        if row.len() as i64 != dest.width {
            dest.error_at = (r, 0);
            dest.error_num = row.len() as i64;
            return ERR_RAGGED;
        }
        for c in 0..dest.width {
            let t = row[c as usize];
            let here = (r, c);
            let mut tile = t;
            if t == b'@' {
                robots += 1;
                if robots > 1 {
                    dest.error_at = here;
                    return ERR_MANY_ROBOTS;
                }
                dest.start = here;
                tile = b'.';
            } else if t == b'$' {
                dest.boxes.push(here);
                tile = b'.';
            } else if t == b'*' {
                dest.boxes.push(here);
                dest.goals.push(here);
                tile = b'G';
            } else if t == b'G' {
                dest.goals.push(here);
            } else if t == b'T' {
                dest.teleporters.push(here);
            } else if t != b'#' && t != b'.' {
                dest.error_at = here;
                dest.error_tile = t;
                return ERR_UNKNOWN_TILE;
            }
            dest.tiles.push(tile);
        }
    }
    if robots == 0 {
        return ERR_NO_ROBOT;
    }
    if dest.teleporters.len() % 2 == 1 {
        dest.error_num = dest.teleporters.len() as i64;
        return ERR_ODD_TELEPORTERS;
    }
    0
}
