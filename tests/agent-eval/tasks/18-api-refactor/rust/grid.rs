// Positions on the map: stepping, bounds, tiles, teleporter pairs, text.
// A position is (row, column), both from 0; row 0 is the top.

use crate::level::Level;

// The position one step from `p` in direction `dir`: 'N' up, 'S' down,
// 'E' right, 'W' left.
pub fn step(p: (i64, i64), dir: u8) -> (i64, i64) {
    let (r, c) = p;
    if dir == b'N' {
        (r - 1, c)
    } else if dir == b'S' {
        (r + 1, c)
    } else if dir == b'E' {
        (r, c + 1)
    } else {
        (r, c - 1)
    }
}

pub fn in_bounds(level: &Level, p: (i64, i64)) -> bool {
    p.0 >= 0 && p.0 < level.height && p.1 >= 0 && p.1 < level.width
}

// The index of `p` in a row-by-row array of the map's cells.
pub fn cell_index(level: &Level, p: (i64, i64)) -> usize {
    (p.0 * level.width + p.1) as usize
}

// The tile at `p`; outside the map everything is wall.
pub fn tile_at(level: &Level, p: (i64, i64)) -> u8 {
    if !in_bounds(level, p) {
        return b'#';
    }
    level.tiles[cell_index(level, p)]
}

// The teleporter paired with the one at `p`: the first with the second in
// reading order, the third with the fourth, and so on.
pub fn partner(level: &Level, p: (i64, i64)) -> (i64, i64) {
    let mut i = 0;
    while level.teleporters[i] != p {
        i += 1;
    }
    level.teleporters[i ^ 1]
}

// Appends "row,col".
pub fn push_pos(out: &mut String, p: (i64, i64)) {
    out.push_str(&p.0.to_string());
    out.push(',');
    out.push_str(&p.1.to_string());
}
