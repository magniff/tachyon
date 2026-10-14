// The level: the map's tiles, where the robot starts, the boxes, the goals
// and the teleporters, and `load_level`, which reads them from the input.

use crate::grid::Pos;

// Why load_level refused a map.
pub enum LoadError {
    EmptyMap,
    NoSeparator,
    // The row, its length, the length expected (the first row's).
    RaggedRow(i64, i64, i64),
    // Where, the tile.
    UnknownTile(Pos, u8),
    NoRobot,
    // Where the second robot is.
    SecondRobot(Pos),
    // How many teleporters there are.
    OddTeleporters(i64),
}

pub struct Level {
    pub height: i64,
    pub width: i64,
    // Row by row: '#' wall, '.' floor, 'G' goal, 'T' teleporter. The robot
    // and the boxes are not in it: their tiles are floor or goal.
    pub tiles: Vec<u8>,
    pub start: Pos,
    // Each in reading order (row by row, left to right).
    pub boxes: Vec<Pos>,
    pub goals: Vec<Pos>,
    pub teleporters: Vec<Pos>,
    // The number of map lines; the '---' line comes after them.
    pub map_lines: i64,
}

impl Level {
    pub fn new() -> Level {
        Level {
            height: 0,
            width: 0,
            tiles: Vec::new(),
            start: Pos::new(0, 0),
            boxes: Vec::new(),
            goals: Vec::new(),
            teleporters: Vec::new(),
            map_lines: 0,
        }
    }
}

// Reads the map from the input's lines: the lines before the first '---'
// line.
pub fn load_level(lines: &[&[u8]]) -> Result<Level, LoadError> {
    let mut sep: i64 = -1;
    for i in 0..lines.len() {
        if lines[i] == b"---" {
            sep = i as i64;
            break;
        }
    }
    if sep < 0 {
        return Err(LoadError::NoSeparator);
    }
    if sep == 0 || lines[0].is_empty() {
        return Err(LoadError::EmptyMap);
    }
    let mut level = Level::new();
    level.map_lines = sep;
    level.height = sep;
    level.width = lines[0].len() as i64;
    let mut robots = 0;
    for r in 0..sep {
        let row = lines[r as usize];
        if row.len() as i64 != level.width {
            return Err(LoadError::RaggedRow(r, row.len() as i64, level.width));
        }
        for c in 0..level.width {
            let t = row[c as usize];
            let here = Pos::new(r, c);
            let mut tile = t;
            if t == b'@' {
                robots += 1;
                if robots > 1 {
                    return Err(LoadError::SecondRobot(here));
                }
                level.start = here;
                tile = b'.';
            } else if t == b'$' {
                level.boxes.push(here);
                tile = b'.';
            } else if t == b'*' {
                level.boxes.push(here);
                level.goals.push(here);
                tile = b'G';
            } else if t == b'G' {
                level.goals.push(here);
            } else if t == b'T' {
                level.teleporters.push(here);
            } else if t != b'#' && t != b'.' {
                return Err(LoadError::UnknownTile(here, t));
            }
            level.tiles.push(tile);
        }
    }
    if robots == 0 {
        return Err(LoadError::NoRobot);
    }
    if level.teleporters.len() % 2 == 1 {
        return Err(LoadError::OddTeleporters(level.teleporters.len() as i64));
    }
    Ok(level)
}
